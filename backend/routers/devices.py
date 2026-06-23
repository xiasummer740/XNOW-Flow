from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import or_
from typing import List, Optional
import json

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
        # Parse tags JSON
        if d.tags:
            try:
                resp.tags = json.loads(d.tags)
            except:
                resp.tags = []
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
    for key, value in update.items():
        if hasattr(device, key):
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
        db.delete(d)
    db.commit()
    return MessageResponse(message=f"已删除 {len(devices)} 台设备")


@router.post("/device-bindings/batch/dispatch/")
def batch_dispatch_task(
    req: DispatchTaskRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """批量下发任务到指定设备"""
    from connection_manager import manager
    from models.task import Task
    from datetime import datetime

    devices = db.query(DeviceBinding).filter(DeviceBinding.id.in_(req.device_ids)).all()
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
        db.add(task)

        # Send via WebSocket if online
        if manager.is_online(d.name):
            import asyncio
            try:
                asyncio.get_event_loop().run_until_complete(
                    manager.send_command(d.name, {
                        "type": "command",
                        "action": req.action,
                        "params": req.params or {},
                        "timestamp": datetime.utcnow().isoformat(),
                    })
                )
                sent_count += 1
            except:
                pass

    db.commit()
    return MessageResponse(message=f"已向 {len(devices)} 台设备下发任务，{sent_count} 台在线已推送")


# ========== Group Management ==========

@router.get("/device-groups/")
def list_groups(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
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
    total = db.query(DeviceBinding).count()
    online = db.query(DeviceBinding).filter(DeviceBinding.is_online == True).count()
    offline = db.query(DeviceBinding).filter(DeviceBinding.is_online == False).count()
    executing = db.query(DeviceBinding).filter(DeviceBinding.device_state == "executing").count()
    return {
        "total": total,
        "online": online,
        "offline": offline,
        "executing": executing,
    }
