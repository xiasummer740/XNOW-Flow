from fastapi import APIRouter, WebSocket, WebSocketDisconnect
import json
import logging

from connection_manager import manager

logger = logging.getLogger(__name__)
router = APIRouter(tags=["websocket"])


@router.websocket("/ws/{device_id}")
async def device_websocket(device_id: str, ws: WebSocket):
    """设备 WebSocket 连接端点

    设备（iOS 插件）通过这个端点连接到后端。
    连接后保持长连接，接收指令并回传状态。
    """
    await manager.connect(device_id, ws)
    try:
        while True:
            # 等待设备发来的消息（状态更新、执行结果等）
            data = await ws.receive_text()
            try:
                msg = json.loads(data)
                msg_type = msg.get("type", "unknown")

                if msg_type == "status":
                    # 设备状态更新
                    logger.info(f"Device {device_id} status: {msg.get('data', {})}")
                elif msg_type == "result":
                    # 任务执行结果回传
                    logger.info(f"Device {device_id} result: {msg.get('data', {})}")
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
