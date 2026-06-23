from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional, Any, Dict

from database import get_db
from models.device import DeviceBinding
from models.task import Task
from models.task_execution import TaskExecution
from schemas.common import MessageResponse
from connection_manager import manager
from dependencies import get_current_user
from models.user import User
from datetime import datetime

router = APIRouter(prefix="/api/biz/v2", tags=["device_commands"])


class CommandRequest(BaseModel):
    action: str
    params: Optional[Dict[str, Any]] = {}


class CommandResponse(BaseModel):
    success: bool
    message: str
    device_online: bool


@router.post("/devices/{device_id}/command/", response_model=CommandResponse)
async def send_device_command(
    device_id: str,
    command: CommandRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """向指定设备发送指令

    Actions: scroll_down, scroll_up, open_profile,
             like, follow, comment, collect, screenshot
    """
    # 检查设备是否存在
    device = db.query(DeviceBinding).filter(
        DeviceBinding.name == device_id
    ).first()
    if not device:
        raise HTTPException(status_code=404, detail="设备不存在")

    # 检查设备是否在线（WebSocket）
    if not manager.is_online(device_id):
        return CommandResponse(
            success=False,
            message="设备不在线，无法下发指令",
            device_online=False,
        )

    # 通过 WebSocket 下发指令
    payload = {
        "type": "command",
        "action": command.action,
        "params": command.params or {},
        "timestamp": datetime.utcnow().isoformat(),
    }

    sent = await manager.send_command(device_id, payload)
    if sent:
        # 记录任务
        task = Task(
            type=command.action,
            name=f"远程指令-{command.action}",
            device=device_id,
            status="running",
            progress=50,
        )
        db.add(task)
        db.commit()

        return CommandResponse(
            success=True,
            message=f"指令已下发: {command.action}",
            device_online=True,
        )
    else:
        return CommandResponse(
            success=False,
            message="指令发送失败",
            device_online=False,
        )


@router.get("/devices/online/")
def get_online_devices(
    current_user: User = Depends(get_current_user),
):
    """获取所有在线设备"""
    return {
        "online_count": manager.get_connection_count(),
        "online_devices": manager.get_online_devices(),
    }
