from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
import hashlib
import time
import threading
import bcrypt
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
    """生成随机 4 位数字 API ID

    注意：SELECT-然后-INSERT 并非原子操作，并发下可能撞唯一约束。
    调用方提交时必须捕获 IntegrityError 并重试（见 login/register）。
    """
    import random
    while True:
        aid = f"{random.randint(0, 9999):04d}"
        if not db.query(User).filter(User.api_id == aid).first():
            return aid

# ---- 登录限流（内存） ----
# key: f"{ip}|{username}" -> (fail_count, first_fail_time, locked_until)
_login_attempts = {}
_login_lock = threading.Lock()
_MAX_ATTEMPTS = 5
_LOCK_SECONDS = 15 * 60  # 15 分钟
_MAX_CACHE_ENTRIES = 10000  # 登录失败记录上限，防止 dict 无限增长

def _check_rate_limit(key: str) -> bool:
    """返回是否允许继续尝试"""
    with _login_lock:
        now = time.time()
        rec = _login_attempts.get(key)
        if not rec:
            return True
        count, first, locked_until = rec
        if locked_until and now < locked_until:
            return False
        # 锁定过期，重置
        if locked_until and now >= locked_until:
            del _login_attempts[key]
            return True
        # 超过阈值且窗口未过 → 锁定
        if count >= _MAX_ATTEMPTS and (now - first) < _LOCK_SECONDS:
            _login_attempts[key] = (count, first, now + _LOCK_SECONDS)
            return False
        return True

def _prune_login_attempts(now: float):
    """记录数超过上限时，清理过期条目（first 早于 2×锁定窗口）"""
    if len(_login_attempts) <= _MAX_CACHE_ENTRIES:
        return
    cutoff = now - 2 * _LOCK_SECONDS
    for key in list(_login_attempts.keys()):
        rec = _login_attempts.get(key)
        if rec and rec[1] < cutoff:
            del _login_attempts[key]
    # 清理后仍超限 → 整体清空（防御性兜底）
    if len(_login_attempts) > _MAX_CACHE_ENTRIES:
        _login_attempts.clear()


def _record_failure(key: str):
    with _login_lock:
        now = time.time()
        rec = _login_attempts.get(key)
        if not rec:
            _login_attempts[key] = (1, now, 0)
        else:
            count, first, locked = rec
            _login_attempts[key] = (count + 1, first, locked)
        _prune_login_attempts(now)

def _clear_attempts(key: str):
    with _login_lock:
        _login_attempts.pop(key, None)

# ---- 密码哈希（bcrypt，兼容旧 sha256） ----
def hash_password(password: str) -> str:
    """新密码用 bcrypt 哈希"""
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()

def verify_password(password: str, stored_hash: str) -> bool:
    """验证密码。兼容旧版 sha256（匹配后自动升级为 bcrypt）"""
    if not stored_hash:
        return False
    # bcrypt 哈希以 $2 开头
    if stored_hash.startswith("$2"):
        try:
            return bcrypt.checkpw(password.encode(), stored_hash.encode())
        except Exception:
            return False
    # 旧版 sha256（64位hex）
    if len(stored_hash) == 64:
        try:
            return hashlib.sha256(password.encode()).hexdigest() == stored_hash
        except Exception:
            return False
    return False

def _upgrade_to_bcrypt(user: User, password: str):
    """登录成功后把 sha256 升级为 bcrypt"""
    if user.password_hash and not user.password_hash.startswith("$2"):
        user.password_hash = hash_password(password)

def create_token(user_id: int) -> str:
    expire = datetime.utcnow() + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    payload = {"user_id": user_id, "exp": expire}
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)

@router.post("/login/", response_model=LoginResponse)
def login(req: LoginRequest, request: Request, db: Session = Depends(get_db)):
    ip = request.client.host if request.client else "unknown"
    key = f"{ip}|{req.username}"
    if not _check_rate_limit(key):
        raise HTTPException(status_code=429, detail="尝试次数过多，请15分钟后再试")

    user = db.query(User).filter(User.username == req.username).first()
    if not user or not verify_password(req.password, user.password_hash or ""):
        _record_failure(key)
        raise HTTPException(status_code=400, detail="用户名或密码错误")
    if not user.is_active:
        raise HTTPException(status_code=400, detail="账户已禁用")

    # 登录成功：清除失败记录，升级密码哈希
    _clear_attempts(key)
    _upgrade_to_bcrypt(user, req.password)

    token = create_token(user.id)
    if not user.api_id:
        # 先持久化密码升级，避免下面 api_id 冲突重试的回滚把密码升级一起冲掉
        db.commit()
        if user.username == "admin":
            user.api_id = "1"
            db.commit()
        else:
            user.api_id = gen_api_id(db)
            for _ in range(50):
                try:
                    db.commit()
                    break
                except IntegrityError:
                    # 并发撞号（唯一约束）→ 回滚后重新生成
                    db.rollback()
                    user.api_id = gen_api_id(db)
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
    if not verify_password(req.old_password, current_user.password_hash or ""):
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
    for _ in range(50):
        api_id = gen_api_id(db)
        user = User(username=req.username, password_hash=hash_password(req.password), role="user", api_id=api_id)
        db.add(user)
        try:
            db.commit()
            break
        except IntegrityError:
            # 并发撞号（唯一约束）→ 回滚后重新生成 api_id
            db.rollback()
    else:
        raise HTTPException(status_code=400, detail="注册失败，请重试")
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
    results = []
    for u in users:
        info = UserInfo(id=u.id, username=u.username, role=u.role, is_active=u.is_active, api_id=u.api_id)
        # 附带商用配额（优先 User override，否则按名下卡算）
        try:
            from quota import get_tenant_quota
            q = get_tenant_quota(db, u.api_id or "") if u.api_id else {}
            info_dict = info.model_dump()
            info_dict.update({
                "device_limit": u.device_limit if u.device_limit is not None else q.get("device_limit"),
                "device_used": q.get("device_used", 0),
                "account_limit": u.account_limit if u.account_limit is not None else q.get("account_limit"),
                "account_used": q.get("account_used", 0),
                "card_count": q.get("card_count", 0),
                "licensed": q.get("licensed", False),
            })
            results.append(info_dict)
        except Exception:
            results.append(info.model_dump())
    return PaginatedResponse(count=len(results), results=results)


@router.patch("/users/{user_id}/quota/", response_model=MessageResponse)
def set_user_quota(
    user_id: int,
    body: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """管理员设置用户租户配额覆盖（null=按名下卡密算）"""
    if current_user.username != "admin":
        raise HTTPException(status_code=403, detail="仅管理员可操作")
    target = db.query(User).filter(User.id == user_id).first()
    if not target:
        raise HTTPException(status_code=404, detail="用户不存在")
    if "device_limit" in body:
        v = body["device_limit"]
        target.device_limit = max(0, int(v)) if v is not None else None
    if "account_limit" in body:
        v = body["account_limit"]
        target.account_limit = max(0, int(v)) if v is not None else None
    db.commit()
    return MessageResponse(message="配额已更新")
