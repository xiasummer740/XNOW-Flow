from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import or_
from typing import List, Optional
import json
import logging

logger = logging.getLogger(__name__)

from database import get_db
from models.device import DeviceBinding
from models.group import DeviceGroup
from schemas.device import (
    DeviceResponse, DeviceGroupResponse, DeviceGroupCreate,
    BatchGroupRequest, BatchDeleteRequest, DispatchTaskRequest
)
from schemas.common import PaginatedResponse, MessageResponse
from dependencies import get_current_user
from models.user import User
from tenant import tenant_scope, ensure_owned

router = APIRouter(prefix="/api/biz/v2", tags=["devices"])

# ========== Device List ==========

@router.get("/device-bindings/")
def list_devices(
    limit: int = Query(20, ge=1, le=200),
    offset: int = Query(0, ge=0),
    search: Optional[str] = Query(None),
    group: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    device_state: Optional[str] = Query(None),
    online: Optional[bool] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(DeviceBinding)

    # 普通用户只能看自己的设备
    if current_user.role != "admin" and current_user.api_id:
        query = query.filter(DeviceBinding.api_id == current_user.api_id)

    # Search by device_id (machine code), name, mobile_no
    if search:
        query = query.filter(
            or_(
                DeviceBinding.device_id.contains(search),
                DeviceBinding.name.contains(search),
                DeviceBinding.mobile_no.contains(search),
                DeviceBinding.device_name.contains(search),
            )
        )

    # Filter by group
    if group and group != "全部":
        if group == "未分组":
            query = query.filter(DeviceBinding.group_name == "未分组")
        else:
            query = query.filter(DeviceBinding.group_name == group)

    # Filter by status
    if status and status != "全部状态":
        if status == "在线":
            query = query.filter(DeviceBinding.is_online == True)
        elif status == "离线":
            query = query.filter(DeviceBinding.is_online == False)
        elif status == "执行中":
            query = query.filter(DeviceBinding.device_state == "executing")
        elif status == "空闲":
            query = query.filter(DeviceBinding.device_state == "idle")

    # Filter by device_state
    if device_state:
        query = query.filter(DeviceBinding.device_state == device_state)

    # Filter by online
    if online is not None:
        query = query.filter(DeviceBinding.is_online == online)

    total = query.count()
    devices = query.order_by(DeviceBinding.id.desc()).offset(offset).limit(limit).all()

    results = []
    for d in devices:
        resp = DeviceResponse.model_validate(d)
        results.append(resp)

    return {"count": total, "next": None, "previous": None, "results": results}


# ========== Single Device Operations ==========

@router.get("/device-bindings/{device_id}/")
def get_device(
    device_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    device = db.query(DeviceBinding).filter(DeviceBinding.id == device_id).first()
    if not device:
        raise HTTPException(status_code=404, detail="设备不存在")
    ensure_owned(device, current_user)
    return DeviceResponse.model_validate(device)


@router.put("/device-bindings/{device_id}/")
def update_device(
    device_id: int,
    update: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    device = db.query(DeviceBinding).filter(DeviceBinding.id == device_id).first()
    if not device:
        raise HTTPException(status_code=404, detail="设备不存在")
    ensure_owned(device, current_user)
    # 阻止越权字段（所有权/主键/密钥）
    blocked = {"id", "api_id", "device_secret", "name", "created_at", "updated_at"}
    for key, value in update.items():
        if key in blocked or not hasattr(device, key):
            continue
        setattr(device, key, value)
    db.commit()
    db.refresh(device)
    return DeviceResponse.model_validate(device)


@router.delete("/device-bindings/{device_id}/")
def delete_device(
    device_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    device = db.query(DeviceBinding).filter(DeviceBinding.id == device_id).first()
    if not device:
        raise HTTPException(status_code=404, detail="设备不存在")
    ensure_owned(device, current_user)
    db.delete(device)
    db.commit()
    return MessageResponse(message="删除成功")


# ========== Batch Operations ==========

@router.post("/device-bindings/batch/group/")
def batch_update_group(
    req: BatchGroupRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    devices = db.query(DeviceBinding).filter(DeviceBinding.id.in_(req.device_ids)).all()
    for d in devices:
        ensure_owned(d, current_user)
        d.group_name = req.group_name
    db.commit()
    return MessageResponse(message=f"已更新 {len(devices)} 台设备的分组")


@router.post("/device-bindings/batch/delete/")
def batch_delete_devices(
    req: BatchDeleteRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    devices = db.query(DeviceBinding).filter(DeviceBinding.id.in_(req.device_ids)).all()
    for d in devices:
        ensure_owned(d, current_user)
        db.delete(d)
    db.commit()
    return MessageResponse(message=f"已删除 {len(devices)} 台设备")


@router.post("/device-bindings/batch/dispatch/")
async def batch_dispatch_task(
    req: DispatchTaskRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """批量下发任务到指定设备"""
    from connection_manager import manager
    from models.task import Task
    from models.account import Account
    from datetime import datetime
    import json

    devices = db.query(DeviceBinding).filter(DeviceBinding.id.in_(req.device_ids)).all()
    for d in devices:
        ensure_owned(d, current_user)

    # 批量登录时，获取账号凭证附带到指令参数
    account_credentials = {}
    if req.action == "batch_login" and req.params and req.params.get("account_ids"):
        accounts_query = db.query(Account).filter(Account.id.in_(req.params["account_ids"]))
        scope = tenant_scope(Account, current_user)
        if scope is not None:
            accounts_query = accounts_query.filter(scope)
        accounts = accounts_query.all()
        for acc in accounts:
            try:
                from crypto import decrypt_credentials
                creds = decrypt_credentials(acc.credentials or "")
                account_credentials[str(acc.id)] = {
                    "id": acc.id,
                    "nickname": acc.nickname,
                    "aweme_number": acc.aweme_number,
                    "password": creds.get("password", ""),
                    "cookies": creds.get("cookies", ""),
                    "token": creds.get("token", ""),
                }
            except (json.JSONDecodeError, TypeError):
                pass

    sent_count = 0
    for d in devices:
        # Record task
        task = Task(
            type=req.action,
            name=f"批量指令-{req.action}",
            device=d.name,
            status="running",
            progress=50,
        )
        if current_user.role != "admin":
            task.api_id = current_user.api_id or ""
        db.add(task)

        # 下发指令（WebSocket 优先，HTTP 轮询设备入队）
        # 始终入队（不再用 is_online 拦截 — 离线设备靠队列延迟送达，避免丢指令）
        payload = {
            "type": "command",
            "action": req.action,
            "params": req.params or {},
            "timestamp": datetime.utcnow().isoformat(),
        }
        if req.action == "batch_login" and account_credentials:
            payload["credentials"] = account_credentials

        try:
            # send_or_enqueue_command: WS可达就发，否则入轮询队列（async直接await）
            sent, via_ws = await manager.send_or_enqueue_command(d.name, payload)
            if sent:
                sent_count += 1
        except Exception as e:
            logger.error(f"dispatch to {d.name} error: {e}")

    db.commit()
    return MessageResponse(message=f"已向 {len(devices)} 台设备下发任务，{sent_count} 台已推送(含队列)")


# ========== Group Management ==========

@router.get("/device-groups/")
def list_groups(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # 说明：DeviceGroup 是全局共享分组（无 api_id 列，无 creator 归属）。
    # 列表对全体用户可见（含管理员创建的分组）；写操作（创建/删除）仅管理员可用。
    groups = db.query(DeviceGroup).order_by(DeviceGroup.id).all()
    # Update device counts
    for g in groups:
        g.device_count = db.query(DeviceBinding).filter(DeviceBinding.group_name == g.name).count()
    db.commit()
    return [DeviceGroupResponse.model_validate(g) for g in groups]


@router.post("/device-groups/", status_code=201)
def create_group(
    req: DeviceGroupCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # 分组为全局共享资源，写操作仅管理员可执行
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="仅管理员可创建分组")
    existing = db.query(DeviceGroup).filter(DeviceGroup.name == req.name).first()
    if existing:
        raise HTTPException(status_code=400, detail="分组已存在")
    group = DeviceGroup(name=req.name, description=req.description)
    db.add(group)
    db.commit()
    db.refresh(group)
    return DeviceGroupResponse.model_validate(group)


@router.delete("/device-groups/{group_id}/")
def delete_group(
    group_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # 分组为全局共享资源，删除仅管理员可执行
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="仅管理员可删除分组")
    group = db.query(DeviceGroup).filter(DeviceGroup.id == group_id).first()
    if not group:
        raise HTTPException(status_code=404, detail="分组不存在")
    # Reset devices in this group to "未分组"
    devices = db.query(DeviceBinding).filter(DeviceBinding.group_name == group.name).all()
    for d in devices:
        d.group_name = "未分组"
    db.delete(group)
    db.commit()
    return MessageResponse(message=f"已删除分组「{group.name}」")


# ========== Quick Stats ==========

@router.get("/device-bindings/stats/summary/")
def device_stats_summary(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(DeviceBinding)
    scope = tenant_scope(DeviceBinding, current_user)
    if scope is not None:
        query = query.filter(scope)
    total = query.count()
    online = query.filter(DeviceBinding.is_online == True).count()
    offline = query.filter(DeviceBinding.is_online == False).count()
    executing = query.filter(DeviceBinding.device_state == "executing").count()
    return {
        "total": total,
        "online": online,
        "offline": offline,
        "executing": executing,
    }
