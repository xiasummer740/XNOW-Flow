"""自动私信任务 — 创建/查询/删除/下发
用于"自动私信"功能：创建私信任务，向设备下发 send_dm 指令
"""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import Optional
from datetime import datetime, timezone
import logging

from database import get_db
from models.dm_task import DmTask
from models.user import User
from dependencies import get_current_user
from tenant import tenant_scope, ensure_owned
from connection_manager import manager

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/biz/v2", tags=["dm_tasks"])

VALID_STATUSES = {"pending", "processing", "done", "failed"}


def _parse_iso_datetime(value):
    """容错解析 ISO8601：接受 naive/aware 与 'Z' 后缀，统一返回 aware UTC。
    解析失败抛 ValueError，由调用方转 400。"""
    s = str(value).strip().replace("Z", "+00:00")
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


@router.post("/dm-tasks/", status_code=201)
def create_dm_task(
    body: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """创建私信任务
    body: {device_id, target_username, content, scheduled_at?}
    """
    device_id = (body.get("device_id") or "").strip()
    content = (body.get("content") or "").strip()
    if not device_id:
        raise HTTPException(status_code=400, detail="device_id 不能为空")
    if not content:
        raise HTTPException(status_code=400, detail="私信内容不能为空")

    target_username = (body.get("target_username") or "").strip()
    scheduled_at = None
    if body.get("scheduled_at"):
        try:
            scheduled_at = _parse_iso_datetime(body["scheduled_at"])
        except Exception:
            raise HTTPException(status_code=400, detail="scheduled_at 格式非法，需 ISO8601")

    task = DmTask(
        device_id=device_id,
        target_username=target_username,
        content=content,
        status="pending",
        scheduled_at=scheduled_at,
        api_id=current_user.api_id or "",
    )
    db.add(task)
    db.commit()
    db.refresh(task)
    return {
        "id": task.id,
        "device_id": task.device_id,
        "target_username": task.target_username,
        "content": task.content,
        "status": task.status,
        "scheduled_at": task.scheduled_at,
        "created_at": task.created_at,
    }


@router.get("/dm-tasks/")
def list_dm_tasks(
    status: Optional[str] = Query(None),
    device_id: Optional[str] = Query(None),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """查询私信任务，可按状态/设备过滤"""
    query = db.query(DmTask)
    scope = tenant_scope(DmTask, current_user)
    if scope is not None:
        query = query.filter(scope)
    if status:
        if status not in VALID_STATUSES:
            raise HTTPException(status_code=400, detail=f"非法状态: {status}，可选 {sorted(VALID_STATUSES)}")
        query = query.filter(DmTask.status == status)
    if device_id:
        query = query.filter(DmTask.device_id == device_id)
    tasks = query.order_by(DmTask.id.desc()).limit(limit).all()
    return {"count": len(tasks), "results": [
        {
            "id": t.id,
            "device_id": t.device_id,
            "target_username": t.target_username,
            "content": t.content,
            "status": t.status,
            "scheduled_at": t.scheduled_at,
            "result": t.result,
            "created_at": t.created_at,
        } for t in tasks
    ]}


@router.delete("/dm-tasks/{task_id}/")
def delete_dm_task(
    task_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """删除私信任务"""
    task = db.query(DmTask).filter(DmTask.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="任务不存在")
    ensure_owned(task, current_user)
    db.delete(task)
    db.commit()
    return {"message": "删除成功"}


@router.post("/dm-tasks/{task_id}/dispatch/")
async def dispatch_dm_task(
    task_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """下发私信指令到设备（WebSocket 直发 → HTTP 轮询队列）"""
    task = db.query(DmTask).filter(DmTask.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="任务不存在")
    ensure_owned(task, current_user)
    if not task.device_id:
        raise HTTPException(status_code=400, detail="任务缺少 device_id")
    from tenant import resolve_owned_device
    if not resolve_owned_device(db, task.device_id, current_user):
        raise HTTPException(status_code=404, detail="设备不存在")

    command = {
        "type": "command",
        "action": "send_dm",
        "params": {
            "target": task.target_username or "",
            "content": task.content or "",
            "dm_id": task.id,
        },
        "timestamp": datetime.utcnow().isoformat(),
    }
    success, via_ws = await manager.send_or_enqueue_command(task.device_id, command)

    # 更新状态为处理中
    task.status = "processing"
    db.commit()

    via = "WebSocket" if via_ws else "HTTP轮询队列"
    return {
        "success": True,
        "message": f"私信指令已下发({via})",
        "via": via,
        "dm_id": task.id,
    }
