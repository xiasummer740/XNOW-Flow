from fastapi import WebSocket
from typing import Dict, Optional
from models.device import DeviceBinding
from database import SessionLocal
from datetime import datetime
import json
import logging

logger = logging.getLogger(__name__)

class ConnectionManager:
    """管理设备连接（WebSocket 长连接 + HTTP 轮询）"""

    def __init__(self):
        self._connections: Dict[str, WebSocket] = {}  # device_id -> websocket
        self._device_info: Dict[str, dict] = {}  # device_id -> metadata
        self._command_queues: Dict[str, list] = {}  # device_id -> [commands]（HTTP轮询用）

    async def connect(self, device_id: str, websocket: WebSocket, api_id: str = "", device_code: str = ""):
        await websocket.accept()
        self._connections[device_id] = websocket
        self._device_info[device_id] = {
            "connected_at": datetime.utcnow().isoformat(),
            "ip": websocket.client.host if websocket.client else "unknown",
            "api_id": api_id,
            "device_code": device_code,
        }
        # Update DB: set device online + store api_id
        self._update_device_status(device_id, online=True, status="online", api_id=api_id)
        logger.info(f"Device {device_id} connected (total: {len(self._connections)}, api_id={api_id})")

    async def disconnect(self, device_id: str):
        if device_id in self._connections:
            del self._connections[device_id]
        if device_id in self._device_info:
            del self._device_info[device_id]
        # Update DB: set device offline
        self._update_device_status(device_id, online=False, status="offline")
        logger.info(f"Device {device_id} disconnected (total: {len(self._connections)})")

    async def send_command(self, device_id: str, command: dict) -> bool:
        """向指定设备发送指令，返回是否发送成功"""
        ws = self._connections.get(device_id)
        if not ws:
            return False
        try:
            await ws.send_json(command)
            return True
        except Exception as e:
            logger.error(f"Send to {device_id} failed: {e}")
            await self.disconnect(device_id)
            return False

    async def broadcast(self, command: dict):
        """向所有在线设备广播指令"""
        disconnected = []
        for device_id, ws in self._connections.items():
            try:
                await ws.send_json(command)
            except Exception:
                disconnected.append(device_id)
        for did in disconnected:
            await self.disconnect(did)

    async def send_or_enqueue_command(self, device_id: str, command: dict) -> tuple:
        """发送指令：优先 WebSocket，不可达则入队等待 HTTP 轮询
        返回 (success, via_websocket)
        """
        # 1) 尝试 WebSocket 发送
        if device_id in self._connections:
            sent = await self.send_command(device_id, command)
            if sent:
                logger.info(f"Command sent via WS to {device_id}: {command.get('action', 'unknown')}")
                return (True, True)
        # 2) WebSocket 不可达 → 入队（只要设备在 DB 中存在就允许入队）
        self.enqueue_command(device_id, command)
        return (True, False)

    async def switch_account(self, device_id: str, aweme_id: str) -> tuple:
        """向设备发送切换账号指令，返回 (success, via_websocket)"""
        cmd = {
            "type": "command",
            "action": "switch_account",
            "params": {"aweme_id": aweme_id},
            "timestamp": datetime.utcnow().isoformat(),
        }
        return await self.send_or_enqueue_command(device_id, cmd)

    def get_online_devices(self) -> list:
        return list(self._connections.keys())

    def is_online(self, device_id: str) -> bool:
        # WebSocket 在线
        if device_id in self._connections:
            return True
        # DB 中 last_online 在 30 秒内（HTTP 轮询设备）
        try:
            db = SessionLocal()
            dev = db.query(DeviceBinding).filter(DeviceBinding.name == device_id).first()
            db.close()
            if dev and dev.last_online:
                delta = (datetime.utcnow() - dev.last_online.replace(tzinfo=None)).total_seconds()
                return delta < 30
        except Exception:
            pass
        return False

    def get_connection_count(self) -> int:
        return len(self._connections)

    # -------- HTTP 轮询命令队列 --------

    def enqueue_command(self, device_id: str, command: dict):
        """为 HTTP 轮询设备入队一条命令"""
        if device_id not in self._command_queues:
            self._command_queues[device_id] = []
        self._command_queues[device_id].append(command)
        logger.info(f"Command queued for {device_id}: {command.get('action', 'unknown')} (total: {len(self._command_queues[device_id])})")

    def dequeue_commands(self, device_id: str) -> list:
        """取出并清空设备的所有积压指令"""
        return self._command_queues.pop(device_id, [])

    def has_pending_commands(self, device_id: str) -> bool:
        """检查设备是否有积压指令"""
        q = self._command_queues.get(device_id)
        return bool(q)

    def clear_queues(self):
        """清空所有命令队列（管理员操作用）"""
        self._command_queues.clear()

    def _update_device_status(self, device_id: str, online: bool, status: str, api_id: str = ""):
        """更新数据库中设备的在线状态，设备不存在时自动注册"""
        try:
            db = SessionLocal()
            device = db.query(DeviceBinding).filter(
                DeviceBinding.name == device_id
            ).first()
            if device:
                device.online = online
                device.status = status
                if api_id:
                    device.api_id = api_id
                if online:
                    device.last_online = datetime.utcnow()
            elif online:
                # 设备首次连接 → 自动注册到数据库
                device = DeviceBinding(
                    name=device_id,
                    device_name=device_id,
                    status=status,
                    online=True,
                    account_count=0,
                    api_id=api_id,
                    last_online=datetime.utcnow(),
                    app_version="—",
                )
                db.add(device)
                logger.info(f"Device {device_id} auto-registered to database (api_id={api_id})")
            db.commit()
            db.close()
        except Exception as e:
            logger.error(f"Update device status failed: {e}")


# 全局单例
manager = ConnectionManager()
