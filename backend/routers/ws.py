from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session
import json
import logging

from connection_manager import manager
from database import SessionLocal
from models.account import Account
from models.device import DeviceBinding

logger = logging.getLogger(__name__)
router = APIRouter(tags=["websocket"])


def _upsert_account(device_id: str, account_data: dict):
    """从设备上报创建或更新账号记录"""
    db = SessionLocal()
    try:
        aweme_id = account_data.get("aweme_id", "")
        if not aweme_id:
            return

        account = db.query(Account).filter(Account.aweme_id == aweme_id).first()
        if account:
            for key, value in account_data.items():
                if hasattr(account, key) and key not in ("aweme_id", "id"):
                    setattr(account, key, value)
            account.device_id = device_id
        else:
            account = Account(
                aweme_id=aweme_id,
                nickname=account_data.get("nickname", ""),
                unique_id=account_data.get("unique_id", ""),
                followers=account_data.get("followers", 0),
                following_count=account_data.get("following_count", 0),
                digg_count=account_data.get("digg_count", 0),
                video_count=account_data.get("video_count", 0),
                signature=account_data.get("signature", ""),
                avatar_url=account_data.get("avatar_url", ""),
                device_id=device_id,
                health_score=account_data.get("health_score", 100),
                status=account_data.get("status", "active"),
                source="device_report",
            )
            db.add(account)

        db.commit()

        # 绑定设备到该账号
        device = db.query(DeviceBinding).filter(
            DeviceBinding.name == device_id
        ).first()
        if device:
            device.current_account_id = account.id
            db.commit()

    except Exception as e:
        logger.error(f"_upsert_account error: {e}")
    finally:
        db.close()


@router.websocket("/ws/{device_id}")
async def device_websocket(device_id: str, ws: WebSocket, api_id: str = "", device_code: str = ""):
    """设备 WebSocket 连接端点

    设备（iOS 插件）通过这个端点连接到后端。
    连接后保持长连接，接收指令并回传状态。
    api_id: 用户 API 标识
    device_code: 设备编号（1-20）
    """
    await manager.connect(device_id, ws, api_id=api_id, device_code=device_code)
    try:
        while True:
            # 等待设备发来的消息（状态更新、执行结果等）
            data = await ws.receive_text()
            try:
                msg = json.loads(data)
                msg_type = msg.get("type", "unknown")

                if msg_type == "status":
                    # 设备状态更新
                    status_data = msg.get("data", {})
                    logger.info(f"Device {device_id} status received")

                    # 如果包含账号信息，更新账号表
                    current_account = status_data.get("current_account")
                    if current_account:
                        _upsert_account(device_id, current_account)

                elif msg_type == "result":
                    # 任务执行结果回传
                    logger.info(f"Device {device_id} result: {msg.get('data', {})}")

                elif msg_type == "account_update":
                    # 设备上报账号信息
                    account_data = msg.get("data", {})
                    logger.info(f"Device {device_id} account update: {account_data.get('nickname', '')}")
                    _upsert_account(device_id, account_data)

                elif msg_type == "account_list":
                    # 设备上报多个账号列表
                    accounts = msg.get("data", [])
                    for acc_data in accounts:
                        _upsert_account(device_id, acc_data)

                elif msg_type == "ping":
                    # 心跳
                    await ws.send_json({"type": "pong"})

                else:
                    await ws.send_json({"type": "error", "message": f"Unknown type: {msg_type}"})

            except json.JSONDecodeError:
                await ws.send_json({"type": "error", "message": "Invalid JSON"})

    except WebSocketDisconnect:
        logger.info(f"Device {device_id} websocket disconnected")
    except Exception as e:
        logger.error(f"WebSocket error for {device_id}: {e}")
    finally:
        await manager.disconnect(device_id)
