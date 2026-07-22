from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
import hashlib
import jwt
from datetime import datetime, timedelta

from database import get_db
from config import settings
from models.user import User
from schemas.auth import LoginRequest, LoginResponse, UserInfo, PasswordChangeRequest, RegisterRequest
from schemas.common import MessageResponse, PaginatedResponse
from dependencies import get_current_user

router = APIRouter(prefix="/api/auth", tags=["auth"])

def gen_api_id(db: Session) -> str:
    """生成随机 4 位数字 API ID"""
    import random
    while True:
        aid = f"{random.randint(0, 9999):04d}"
        if not db.query(User).filter(User.api_id == aid).first():
            return aid

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
    if not user.api_id:
        user.api_id = "1" if user.username == "admin" else gen_api_id(db)
        db.commit()
    if not user.role:
        user.role = "admin" if user.username == "admin" else "user"
        db.commit()
    return LoginResponse(
        token=token,
        user=UserInfo(id=user.id, username=user.username, role=user.role, is_active=user.is_active, api_id=user.api_id)
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


@router.post("/register/", response_model=LoginResponse)
def register(req: RegisterRequest, db: Session = Depends(get_db),
             current_user: User = Depends(get_current_user)):
    """管理员创建用户（仅 admin 可用）"""
    if current_user.username != "admin":
        raise HTTPException(status_code=403, detail="仅管理员可创建用户")
    if db.query(User).filter(User.username == req.username).first():
        raise HTTPException(status_code=400, detail="用户名已存在")
    if req.username == "admin":
        raise HTTPException(status_code=400, detail="不能创建 admin 账号")
    api_id = gen_api_id(db)
    user = User(username=req.username, password_hash=hash_password(req.password), role="user", api_id=api_id)
    db.add(user)
    db.commit()
    db.refresh(user)
    return LoginResponse(
        token=create_token(user.id),
        user=UserInfo(id=user.id, username=user.username, role="user", is_active=user.is_active, api_id=user.api_id)
    )


@router.get("/users/", response_model=PaginatedResponse)
def list_users(db: Session = Depends(get_db),
               current_user: User = Depends(get_current_user)):
    """管理员查看所有用户（仅 admin 可用）"""
    if current_user.username != "admin":
        raise HTTPException(status_code=403, detail="仅管理员可查看")
    users = db.query(User).all()
    results = [UserInfo(id=u.id, username=u.username, role=u.role, is_active=u.is_active, api_id=u.api_id) for u in users]
    return PaginatedResponse(count=len(results), results=results)
