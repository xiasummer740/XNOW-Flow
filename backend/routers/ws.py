from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Request
import json
import logging
from datetime import datetime

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


def _handle_device_message(device_id: str, msg: dict):
    """处理设备上报的消息（WebSocket 和 HTTP 轮询共用）"""
    msg_type = msg.get("type", "unknown")

    if msg_type == "status":
        status_data = msg.get("data", {})
        logger.info(f"Device {device_id} status received via HTTP")

        # 如果包含 api_id，更新设备
        api_id = status_data.get("api_id", "")
        device_code = status_data.get("device_code", "")
        if api_id:
            _mark_device_online(device_id, api_id, device_code)

        # 更新 App 版本（应用程序列）
        app_version = status_data.get("app_version", "")
        if app_version:
            try:
                db = SessionLocal()
                dev = db.query(DeviceBinding).filter(DeviceBinding.name == device_id).first()
                if dev:
                    dev.app_version = app_version
                    db.commit()
                db.close()
            except Exception as e:
                logger.error(f"update app_version error: {e}")

        current_account = status_data.get("current_account")
        if current_account:
            _upsert_account(device_id, current_account)

    elif msg_type == "result":
        logger.info(f"Device {device_id} result: {msg.get('data', {})}")

    elif msg_type == "account_update":
        account_data = msg.get("data", {})
        logger.info(f"Device {device_id} account update: {account_data.get('nickname', '')}")
        _upsert_account(device_id, account_data)

    elif msg_type == "account_list":
        accounts = msg.get("data", [])
        for acc_data in accounts:
            _upsert_account(device_id, acc_data)

    elif msg_type == "bind_info":
        bind_data = msg.get("data", {})
        device_code = bind_data.get("device_code", "")
        api_id = bind_data.get("api_id", "")
        logger.info(f"Device {device_id} bound: code={device_code}, api_id={api_id}")
        _mark_device_online(device_id, api_id, device_code)

        # 更新设备记录
        db = SessionLocal()
        try:
            dev = db.query(DeviceBinding).filter(DeviceBinding.name == device_id).first()
            if dev:
                dev.api_id = api_id
                if device_code:
                    dev.name = device_code
                db.commit()
                logger.info(f"Device {device_id} updated with api_id={api_id}")
        except Exception as e:
            logger.error(f"bind_info error: {e}")
        finally:
            db.close()

    elif msg_type == "ping":
        pass  # HTTP 轮询的 ping 不需要回复

    else:
        logger.info(f"Device {device_id} unknown message type: {msg_type}")


def _mark_device_online(device_id: str, api_id: str = "", device_code: str = ""):
    """标记设备在线（用于 HTTP 轮询设备）"""
    try:
        db = SessionLocal()
        device = db.query(DeviceBinding).filter(
            DeviceBinding.name == device_id
        ).first()
        if device:
            device.online = True
            device.is_online = True  # 前端用 is_online 判断在线
            device.status = "online"
            if api_id:
                device.api_id = api_id
            # 机器码：设备唯一标识（用于区分多台设备）
            if not device.device_id:
                device.device_id = device_id
            device.last_online = datetime.utcnow()
        else:
            device = DeviceBinding(
                name=device_id,
                device_name=device_id,
                device_id=device_id,  # 机器码 = 设备唯一ID
                status="online",
                online=True,
                is_online=True,  # 前端用 is_online 判断在线
                account_count=0,
                api_id=api_id,
                last_online=datetime.utcnow(),
                app_version="—",
            )
            db.add(device)
            logger.info(f"Device {device_id} auto-registered via HTTP poll")
        db.commit()
        db.close()
    except Exception as e:
        logger.error(f"_mark_device_online error: {e}")


# ========== WebSocket 端点（向后兼容） ==========
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

                elif msg_type == "bind_info":
                    # 设备绑定信息上报
                    bind_data = msg.get("data", {})
                    device_code = bind_data.get("device_code", "")
                    api_id = bind_data.get("api_id", "")
                    logger.info(f"Device {device_id} bound: code={device_code}, api_id={api_id}")
                    # 更新设备记录
                    db = SessionLocal()
                    try:
                        dev = db.query(DeviceBinding).filter(DeviceBinding.name == device_id).first()
                        if dev:
                            dev.api_id = api_id
                            if device_code:
                                dev.name = device_code
                            db.commit()
                            logger.info(f"Device {device_id} updated with api_id={api_id}")
                    except Exception as e:
                        logger.error(f"bind_info error: {e}")
                    finally:
                        db.close()
                    await ws.send_json({"type": "bind_info_ack", "data": {"status": "ok"}})

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


# ========== HTTP 轮询端点（避开 BH TikTok 长连接检测） ==========

@router.post("/ws/{device_id}")
async def device_http_post(device_id: str, request: Request):
    """设备通过 HTTP POST 上报数据

    替代 WebSocket 的消息通道，每次请求短连接。
    设备定时 POST 上报状态/账号/结果，同时带回积压指令。
    """
    try:
        body = await request.json()
    except Exception:
        return {"status": "error", "message": "Invalid JSON"}

    msg_type = body.get("type", "unknown")

    # 处理消息（与 WebSocket 共用处理函数）
    _handle_device_message(device_id, body)

    # 标记设备最近活跃（更新 last_online）
    api_id = body.get("data", {}).get("api_id", "") if isinstance(body.get("data"), dict) else ""
    _mark_device_online(device_id, api_id)

    # 返回 pending 指令（如果有）
    pending = manager.dequeue_commands(device_id)
    response = {"status": "ok"}

    if msg_type == "bind_info":
        response["ack"] = {"type": "bind_info_ack", "data": {"status": "ok"}}

    if msg_type == "ping":
        response["pong"] = True

    if pending:
        # 如果有多条，一次只返回第一条，剩余的留在队列中
        # 但实际上 dequeue_commands 已经清空了队列
        # 所以额外的命令需要重新入队
        command = pending[0]
        if len(pending) > 1:
            for extra in pending[1:]:
                manager.enqueue_command(device_id, extra)
        response["command"] = command
        logger.info(f"Sent command to {device_id} via POST response: {command.get('action', 'unknown')}")

    return response


@router.get("/ws/{device_id}/poll")
async def device_http_poll(device_id: str):
    """设备轮询获取积压指令

    设备定时（每 5 秒）GET 此端点，获取服务端下发的指令。
    无指令时返回 204 No Content。
    """
    # 轮询也更新在线状态（前端用 is_online/last_online 判断设备在线）
    _mark_device_online(device_id)

    pending = manager.dequeue_commands(device_id)
    if not pending:
        from fastapi.responses import Response
        return Response(status_code=204)

    # 一条一条返回，第一条直接返回，其余的重新入队
    command = pending[0]
    if len(pending) > 1:
        for extra in pending[1:]:
            manager.enqueue_command(device_id, extra)

    logger.info(f"Device {device_id} polled command: {command.get('action', 'unknown')}")
    return command
