from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
import hashlib
import jwt
from datetime import datetime, timedelta

from database import get_db
from config import settings
from models.user import User
from schemas.auth import LoginRequest, LoginResponse, UserInfo, PasswordChangeRequest
from schemas.common import MessageResponse
from dependencies import get_current_user

router = APIRouter(prefix="/api/auth", tags=["auth"])

def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()

def create_token(user_id: int) -> str:
    expire = datetime.utcnow() + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    payload = {"user_id": user_id, "exp": expire}
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)

@router.post("/login/", response_model=LoginResponse)
def login(req: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.username == req.username).first()
    if not user or user.password_hash != hash_password(req.password):
        raise HTTPException(status_code=400, detail="用户名或密码错误")
    if not user.is_active:
        raise HTTPException(status_code=400, detail="账户已禁用")

    token = create_token(user.id)
    return LoginResponse(
        token=token,
        user=UserInfo(id=user.id, username=user.username, is_active=user.is_active)
    )

@router.post("/password/", response_model=MessageResponse)
def change_password(
    req: PasswordChangeRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.password_hash != hash_password(req.old_password):
        raise HTTPException(status_code=400, detail="原密码错误")
    if len(req.new_password) < 6:
        raise HTTPException(status_code=400, detail="新密码至少6位")

    current_user.password_hash = hash_password(req.new_password)
    db.commit()
    return MessageResponse(message="密码修改成功")
