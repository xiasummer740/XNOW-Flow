from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional, Any, Dict
import logging

from database import get_db, SessionLocal
from models.device import DeviceBinding
from models.task import Task
from models.task_execution import TaskExecution
from schemas.common import MessageResponse
from connection_manager import manager
from dependencies import get_current_user
from models.user import User
from datetime import datetime

logger = logging.getLogger(__name__)

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
    # 检查设备是否存在 + 归属校验
    from tenant import resolve_owned_device
    device = resolve_owned_device(db, device_id, current_user)
    if not device:
        raise HTTPException(status_code=404, detail="设备不存在")

    # 构建指令载荷
    payload = {
        "type": "command",
        "action": command.action,
        "params": command.params or {},
        "timestamp": datetime.utcnow().isoformat(),
    }

    # 尝试发送（WebSocket 直发 → HTTP 轮询队列）
    success, via_ws = await manager.send_or_enqueue_command(device_id, payload)

    # 记录任务
    task = Task(
        type=command.action,
        name=f"远程指令-{command.action}",
        device=device_id,
        status="running",
        progress=50,
    )
    if current_user.role != "admin":
        task.api_id = current_user.api_id or ""
    db.add(task)
    db.commit()

    via = "WebSocket" if via_ws else "HTTP轮询队列"
    return CommandResponse(
        success=True,
        message=f"指令已下发({via}): {command.action}",
        device_online=True,
    )


@router.post("/commands/report/")
async def report_command(data: Dict[str, Any], secret: str = ""):
    """手机端浮窗上报指令（替代 WebSocket，兼容 HTTP）"""
    from routers.ws import _verify_device_auth
    action = data.get("action", "unknown")
    device_id = data.get("device_id", "unknown")
    params = data.get("params", {})
    # M5: 设备密钥鉴权（防止伪造上报）
    if not _verify_device_auth(device_id, secret):
        from fastapi import HTTPException
        raise HTTPException(status_code=401, detail="unauthorized")
    logger.info(f"📱 Phone command [{action}] from {device_id}: {params}")
    # 记录到 task 表
    db = SessionLocal()
    try:
        dev = db.query(DeviceBinding).filter(DeviceBinding.name == device_id).first()
        task = Task(
            type=action,
            name=f"手机指令-{action}",
            device=device_id,
            status="success",
            progress=100,
            api_id=(dev.api_id if dev else "") or "",
        )
        db.add(task)
        db.commit()
    except Exception as e:
        logger.error(f"记录指令失败: {e}")
    finally:
        db.close()
    return {"status": "ok", "action": action, "device_id": device_id}


@router.post("/devices/{device_id}/account-report/")
async def report_account(device_id: str, data: Dict[str, Any]):
    """手机端上报当前账号信息"""
    logger.info(f"📱 Account report from {device_id}: {data}")
    return {"status": "ok", "device_id": device_id}


@router.get("/devices/online/")
def get_online_devices(
    current_user: User = Depends(get_current_user),
):
    """获取所有在线设备"""
    return {
        "devices": manager.get_online_devices(),
    }


@router.get("/devices/{device_id}/ui-scan/")
def get_last_ui_scan(
    device_id: str,
    current_user: User = Depends(get_current_user),
):
    """读取设备最近一次 ui_scan 上报结果（内存缓存，页面识别用）"""
    from routers.ws import _last_ui_scan

    data = _last_ui_scan.get(device_id)
    if data is None:
        return {"device_id": device_id, "has_scan": False}
    return {"device_id": device_id, "has_scan": True, **data}
