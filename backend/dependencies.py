from fastapi import Depends, HTTPException, status, Request
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
import jwt
from typing import Optional

from config import settings
from database import get_db
from models.user import User

async def get_token_from_header(request: Request) -> str:
    """从 Authorization header 提取 token，兼容 Token 和 Bearer 前缀"""
    auth = request.headers.get("Authorization", "")
    for prefix in ("Token ", "Bearer "):
        if auth.startswith(prefix):
            return auth[len(prefix):]
    raise HTTPException(status_code=401, detail="无效的认证头")


def get_token_optional(request: Request) -> str:
    """可选 token 提取：无 Authorization header 返回空串（供双鉴权端点用，不抛 401）"""
    auth = request.headers.get("Authorization", "")
    for prefix in ("Token ", "Bearer "):
        if auth.startswith(prefix):
            return auth[len(prefix):]
    return ""


def get_optional_user(
    db: Session = Depends(get_db),
    token: str = Depends(get_token_optional),
) -> Optional[User]:
    """可选用户鉴权：无/无效 token 返回 None，有效返回 User（供设备+后台双鉴权端点用）"""
    if not token:
        return None
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        user_id = payload.get("user_id")
        if user_id is None:
            return None
    except jwt.PyJWTError:
        return None
    user = db.query(User).filter(User.id == user_id).first()
    if user is None or not user.is_active:
        return None
    return user

def get_current_user(
    db: Session = Depends(get_db),
    token: str = Depends(get_token_from_header),
) -> User:
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        user_id = payload.get("user_id")
        if user_id is None:
            raise HTTPException(status_code=401, detail="无效的 token")
    except jwt.PyJWTError:
        raise HTTPException(status_code=401, detail="无效的 token")

    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=401, detail="用户不存在")
    if not user.is_active:
        raise HTTPException(status_code=401, detail="账户已禁用")
    return user
