from fastapi import WebSocket
from typing import Dict, Optional
from models.device import DeviceBinding
from database import SessionLocal
from datetime import datetime
import json
import logging

logger = logging.getLogger(__name__)

class ConnectionManager:
    """管理设备 WebSocket 长连接"""

    def __init__(self):
        self._connections: Dict[str, WebSocket] = {}  # device_id -> websocket
        self._device_info: Dict[str, dict] = {}  # device_id -> metadata

    async def connect(self, device_id: str, websocket: WebSocket):
        await websocket.accept()
        self._connections[device_id] = websocket
        self._device_info[device_id] = {
            "connected_at": datetime.utcnow().isoformat(),
            "ip": websocket.client.host if websocket.client else "unknown",
        }
        # Update DB: set device online
        self._update_device_status(device_id, online=True, status="online")
        logger.info(f"Device {device_id} connected (total: {len(self._connections)})")

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

    def get_online_devices(self) -> list:
        return list(self._connections.keys())

    def is_online(self, device_id: str) -> bool:
        return device_id in self._connections

    def get_connection_count(self) -> int:
        return len(self._connections)

    def _update_device_status(self, device_id: str, online: bool, status: str):
        """更新数据库中设备的在线状态，设备不存在时自动注册"""
        try:
            db = SessionLocal()
            device = db.query(DeviceBinding).filter(
                DeviceBinding.name == device_id
            ).first()
            if device:
                device.online = online
                device.status = status
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
                    last_online=datetime.utcnow(),
                    app_version="—",
                )
                db.add(device)
                logger.info(f"Device {device_id} auto-registered to database")
            db.commit()
            db.close()
        except Exception as e:
            logger.error(f"Update device status failed: {e}")


# 全局单例
manager = ConnectionManager()
