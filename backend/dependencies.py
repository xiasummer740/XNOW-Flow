from fastapi import Depends, HTTPException, status, Request
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
import jwt

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
    return user
