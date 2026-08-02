"""快捷指令（快捷指令库）— 创建/查询/删除/下发

把常用指令（like/follow/smart_browse/register_account 等）保存为快捷指令，
后续选择设备一键下发。
"""
import json
import logging
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import Optional

from database import get_db
from models.quick_command import QuickCommand
from models.user import User
from dependencies import get_current_user
from tenant import tenant_scope, ensure_owned
from connection_manager import manager

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/biz/v2", tags=["quick_commands"])


def _parse_params(text) -> dict:
    if isinstance(text, dict):
        return text
    if not text:
        return {}
    try:
        parsed = json.loads(text)
        return parsed if isinstance(parsed, dict) else {}
    except (json.JSONDecodeError, TypeError):
        return {}


def _serialize_qc(q: QuickCommand) -> dict:
    return {
        "id": q.id,
        "name": q.name,
        "action": q.action,
        "params": _parse_params(q.params),
        "description": q.description,
        "api_id": q.api_id,
        "created_at": q.created_at.isoformat() if q.created_at else None,
    }


@router.post("/quick-commands/", status_code=201)
def create_quick_command(
    body: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """创建快捷指令
    body: {name, action, params?: dict|str, description?}
    """
    name = (body.get("name") or "").strip()
    action = (body.get("action") or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="快捷指令名称不能为空")
    if not action:
        raise HTTPException(status_code=400, detail="指令 action 不能为空")

    params = body.get("params")
    if isinstance(params, dict):
        params = json.dumps(params, ensure_ascii=False)
    elif params is None:
        params = "{}"
    else:
        params = str(params)

    qc = QuickCommand(
        name=name,
        action=action,
        params=params,
        description=(body.get("description") or "").strip(),
        api_id=current_user.api_id or "",
    )
    db.add(qc)
    db.commit()
    db.refresh(qc)
    return _serialize_qc(qc)


@router.get("/quick-commands/")
def list_quick_commands(
    action: Optional[str] = Query(None),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """查询快捷指令，可按 action 过滤（tenant 隔离）"""
    query = db.query(QuickCommand)
    scope = tenant_scope(QuickCommand, current_user)
    if scope is not None:
        query = query.filter(scope)
    if action:
        query = query.filter(QuickCommand.action == action)
    qcs = query.order_by(QuickCommand.id.desc()).limit(limit).all()
    return {"count": len(qcs), "results": [_serialize_qc(q) for q in qcs]}


@router.delete("/quick-commands/{cmd_id}/")
def delete_quick_command(
    cmd_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """删除快捷指令"""
    qc = db.query(QuickCommand).filter(QuickCommand.id == cmd_id).first()
    if not qc:
        raise HTTPException(status_code=404, detail="快捷指令不存在")
    ensure_owned(qc, current_user)
    db.delete(qc)
    db.commit()
    return {"message": "删除成功"}


@router.post("/quick-commands/{cmd_id}/dispatch/")
async def dispatch_quick_command(
    cmd_id: int,
    body: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """把保存的快捷指令下发到指定设备
    body: {device_id: 设备机器码}
    """
    qc = db.query(QuickCommand).filter(QuickCommand.id == cmd_id).first()
    if not qc:
        raise HTTPException(status_code=404, detail="快捷指令不存在")
    ensure_owned(qc, current_user)

    device_id = (body.get("device_id") or "").strip()
    if not device_id:
        raise HTTPException(status_code=400, detail="device_id 不能为空")
    from tenant import resolve_owned_device
    if not resolve_owned_device(db, device_id, current_user):
        raise HTTPException(status_code=404, detail="设备不存在")

    command = {
        "type": "command",
        "action": qc.action,
        "params": _parse_params(qc.params),
        "timestamp": datetime.utcnow().isoformat(),
    }
    success, via_ws = await manager.send_or_enqueue_command(device_id, command)

    via = "WebSocket" if via_ws else "HTTP轮询队列"
    return {
        "success": True,
        "message": f"快捷指令「{qc.name}」已下发({via}): {qc.action}",
        "via": via,
        "command_id": qc.id,
    }
