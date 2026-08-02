"""凭证加密工具 — 用 Fernet(对称加密) 保护账号密码/cookie/token
密钥从 SECRET_KEY 派生，不额外存储。
存储格式: "enc:v1:<fernet_token>"，老数据为明文 JSON（读取时兼容迁移）
"""
import json
import base64
import hashlib
import logging

from cryptography.fernet import Fernet
from config import settings

logger = logging.getLogger(__name__)

_fernet = None


def _get_fernet() -> Fernet:
    global _fernet
    if _fernet is None:
        # 从 SECRET_KEY 派生 32 字节密钥（Fernet 要求）
        key = hashlib.sha256(settings.SECRET_KEY.encode()).digest()
        _fernet = Fernet(base64.urlsafe_b64encode(key))
    return _fernet


def encrypt_credentials(creds: dict) -> str:
    """加密凭证 dict，返回存储字符串"""
    if not creds:
        return ""
    try:
        token = _get_fernet().encrypt(json.dumps(creds, ensure_ascii=False).encode())
        return "enc:v1:" + token.decode()
    except Exception as e:
        # 加密失败时保留明文兜底（不阻断数据导入），但必须大声记录，便于发现
        logger.error(f"encrypt_credentials 加密失败，已降级为明文存储: {e}")
        return json.dumps(creds, ensure_ascii=False)


def decrypt_credentials(stored: str) -> dict:
    """解密存储的凭证字符串，返回 dict。
    兼容旧明文 JSON：解密失败则按明文解析。"""
    if not stored:
        return {}
    try:
        if stored.startswith("enc:v1:"):
            token = stored[len("enc:v1:"):].encode()
            raw = _get_fernet().decrypt(token).decode()
            data = json.loads(raw)
            return data if isinstance(data, dict) else {}
        # 旧明文
        data = json.loads(stored)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def has_credentials(stored: str) -> bool:
    """判断是否存有有效凭证"""
    d = decrypt_credentials(stored)
    return bool(d.get("password") or d.get("cookies") or d.get("token"))
