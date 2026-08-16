"""卡密授权系统

- 管理员生成卡密（批量）、查看、禁用
- 设备输入卡密激活（绑定 device_id + UDID，1年有效）
- 设备连接时校验授权
"""
import secrets
import string
import logging
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from routers.ws import _extract_device_secret
from sqlalchemy.orm import Session

from database import get_db, SessionLocal
from models.license import License
from models.device import DeviceBinding
from models.user import User
from quota import get_tenant_quota, ensure_device_bindable, ensure_account_importable
from dependencies import get_current_user
from tenant import ensure_owned

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/biz/v2", tags=["licenses"])

# 套餐配额（天 / 设备上限 / 账号上限）
PLAN_QUOTA = {
    "month1": {"days": 30,  "device_limit": 3,  "account_limit": 30},
    "month3": {"days": 90,  "device_limit": 8,  "account_limit": 80},
    "year1":  {"days": 365, "device_limit": 20, "account_limit": 200},
}
PLAN_DAYS = {k: v["days"] for k, v in PLAN_QUOTA.items()}  # 兼容旧引用


def _gen_key() -> str:
    """生成卡密: 16位大写字母+数字连体（无横杠/空格，避免用户理解错误）"""
    alphabet = string.ascii_uppercase + string.digits
    # 去除易混淆字符
    for ch in "O0I1":
        alphabet = alphabet.replace(ch, "")
    return "".join(secrets.choice(alphabet) for _ in range(16))


def _normalize_key(raw: str) -> str:
    """卡密归一化：去掉横杠/空格/其他分隔符，统一大写。
    支持 GQGU-BWQG-ZWCA-YV9Z / GQGU BWQG ZWCA YV9Z / gqgubwqgzwcayv9z 任意格式。
    """
    return "".join(ch for ch in (raw or "").upper() if ch.isalnum())


def _serialize(lic: License):
    return {
        "id": lic.id,
        "key": lic.key,
        "plan": lic.plan,
        "status": lic.status,
        "device_id": lic.device_id,
        "udid": lic.udid,
        "api_id": lic.api_id,
        "activated_at": lic.activated_at.isoformat() if lic.activated_at else None,
        "expires_at": lic.expires_at.isoformat() if lic.expires_at else None,
        "remark": lic.remark,
        "device_limit": lic.device_limit,
        "account_limit": lic.account_limit,
        "created_at": lic.created_at.isoformat() if lic.created_at else None,
    }


# ========== 管理员：卡密管理 ==========

@router.post("/licenses/generate/")
def generate_licenses(
    body: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """批量生成卡密（仅 admin）
    body: {count: 数量, plan: 'year1', remark: 备注}
    """
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="仅管理员可生成卡密")
    count = int(body.get("count") or 1)
    count = max(1, min(count, 1000))
    plan = body.get("plan") or "year1"
    if plan not in PLAN_DAYS:
        raise HTTPException(status_code=400, detail=f"无效套餐: {plan}")
    remark = body.get("remark") or ""
    keys = []
    for _ in range(count):
        lic = License(key=_gen_key(), plan=plan, remark=remark, api_id=current_user.api_id or "")
        db.add(lic)
        keys.append(lic.key)
    db.commit()
    logger.info(f"Admin generated {count} license keys (plan={plan})")
    return {"count": count, "keys": keys}


@router.get("/licenses/")
def list_licenses(
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    status: str = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """查看卡密列表（admin 全部，普通用户自己的）"""
    query = db.query(License)
    if current_user.role != "admin":
        query = query.filter(License.api_id == (current_user.api_id or ""))
    if status:
        query = query.filter(License.status == status)
    total = query.count()
    items = query.order_by(License.id.desc()).offset(offset).limit(limit).all()
    return {"count": total, "results": [_serialize(l) for l in items]}


@router.post("/licenses/{license_id}/disable/")
def disable_license(
    license_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """禁用卡密（仅 admin）"""
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="仅管理员可操作")
    lic = db.query(License).filter(License.id == license_id).first()
    if not lic:
        raise HTTPException(status_code=404, detail="卡密不存在")
    lic.status = "disabled"
    db.commit()
    return {"message": "已禁用"}


@router.post("/licenses/{license_id}/quota/")
def set_license_quota(
    license_id: int,
    body: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """管理员调整单卡配额（device_limit/account_limit，None=恢复套餐默认）"""
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="仅管理员可操作")
    lic = db.query(License).filter(License.id == license_id).first()
    if not lic:
        raise HTTPException(status_code=404, detail="卡密不存在")
    if "device_limit" in body:
        v = body["device_limit"]
        lic.device_limit = max(0, int(v)) if v is not None else None
    if "account_limit" in body:
        v = body["account_limit"]
        lic.account_limit = max(0, int(v)) if v is not None else None
    db.commit()
    db.refresh(lic)
    return _serialize(lic)


# ========== 租户配额查询 ==========

@router.get("/quota/")
def get_my_quota(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """当前用户租户的配额使用情况"""
    if current_user.role == "admin":
        # admin 不限额，返回空信息
        return {"admin": True}
    return get_tenant_quota(db, current_user.api_id or "")


# ========== 设备：激活/校验 ==========

@router.post("/licenses/activate/")
def activate_license(
    body: dict,
    db: Session = Depends(get_db),
    secret: str = Depends(_extract_device_secret),
):
    """设备输入卡密激活（设备级操作，用设备密钥 secret 鉴权，不要求管理员 JWT）
    body: {key, device_id, udid}
    成功绑定设备，有效期按套餐（默认1年）。
    """
    # 设备密钥鉴权（设备请求带 ?secret=xxx）
    from routers.ws import _verify_device_auth
    device_id_pre = (body.get("device_id") or "").strip()
    if not _verify_device_auth(device_id_pre, secret):
        raise HTTPException(status_code=401, detail="设备密钥无效")
    key_norm = _normalize_key(body.get("key"))
    device_id = (body.get("device_id") or "").strip()
    udid = (body.get("udid") or "").strip()
    if not key_norm or not device_id:
        raise HTTPException(status_code=400, detail="缺少卡密或设备ID")

    # 归一化匹配：兼容带/不带横杠、空格、大小写
    lic = next(
        (l for l in db.query(License).all() if _normalize_key(l.key) == key_norm),
        None,
    )
    if not lic:
        raise HTTPException(status_code=400, detail="卡密不存在")
    if lic.status == "disabled":
        raise HTTPException(status_code=400, detail="卡密已被禁用")

    now = datetime.utcnow()

    # 已激活且绑定到其他设备 → 拒绝
    if lic.status == "active" and lic.device_id and lic.device_id != device_id:
        raise HTTPException(status_code=400, detail="卡密已绑定其他设备")

    # 未使用 → 激活
    if lic.status in ("unused", "expired"):
        lic.status = "active"
        lic.device_id = device_id
        lic.udid = udid
        lic.activated_at = now
        days = PLAN_DAYS.get(lic.plan, 365)
        lic.expires_at = now + timedelta(days=days)
    elif lic.status == "active" and lic.device_id == device_id:
        # 已激活本设备：如果过期则续期
        if lic.expires_at and lic.expires_at.replace(tzinfo=None) < now:
            days = PLAN_DAYS.get(lic.plan, 365)
            lic.expires_at = now + timedelta(days=days)
            lic.status = "active"

    # 归属回写（双保险）：若设备已绑定租户，把卡归到该租户（主路径在设备绑后台时）
    if not lic.api_id or lic.api_id in ("", "1"):
        dev = db.query(DeviceBinding).filter(DeviceBinding.name == device_id).first()
        if dev and dev.api_id:
            lic.api_id = dev.api_id
            logger.info(f"License {key_norm} api_id backfilled -> {dev.api_id} (device {device_id})")

    db.commit()
    db.refresh(lic)
    logger.info(f"Device {device_id} activated license {key_norm} (plan={lic.plan})")

    return _serialize(lic)


@router.get("/licenses/device/{device_id}/")
def check_device_license(
    device_id: str,
    db: Session = Depends(get_db),
    secret: str = Depends(_extract_device_secret),
):
    """检查设备当前授权状态（连接时调用，设备密钥鉴权）

    用设备唯一标识(device_id 或 udid)查卡：兼容旧数据(device_id)和新版(udid)。
    """
    from routers.ws import _verify_device_auth
    if not _verify_device_auth(device_id, secret):
        raise HTTPException(status_code=401, detail="设备密钥无效")
    from sqlalchemy import or_
    lic = db.query(License).filter(
        or_(
            License.device_id == device_id,
            License.udid == device_id,
        ),
        License.status == "active",
    ).first()
    now = datetime.utcnow()
    if not lic:
        return {"licensed": False, "status": "none", "message": "未激活"}
    expired = lic.expires_at and lic.expires_at.replace(tzinfo=None) < now
    if expired:
        lic.status = "expired"
        db.commit()
        return {"licensed": False, "status": "expired", "message": "授权已过期"}
    return {
        "licensed": True,
        "status": "active",
        "plan": lic.plan,
        "expires_at": lic.expires_at.isoformat() if lic.expires_at else None,
        "days_left": (lic.expires_at.replace(tzinfo=None) - now).days if lic.expires_at else 0,
    }
