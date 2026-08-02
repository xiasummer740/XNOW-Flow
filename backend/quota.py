"""商用配额：设备/账号数按卡密套餐限制

模型（一卡一机）：
- 设备配额 = 租户名下 active 未过期卡张数（每张卡绑一台设备，天然一卡一机）
- 账号配额 = Σ 每张卡套餐 account_limit
- User.device_limit/account_limit 非 NULL 时优先（管理员直接设的租户上限）

严格模式：设备绑定后台 / 导入账号前，租户必须有一张 active 未过期卡，
否则 403「未激活，请先输入卡密」。
"""
import logging
from datetime import datetime

from fastapi import HTTPException

logger = logging.getLogger(__name__)


def _is_effective(lic, now=None) -> bool:
    """卡密是否有效：status=active 且未过期"""
    if lic.status != "active":
        return False
    now = now or datetime.utcnow()
    if lic.expires_at and lic.expires_at.replace(tzinfo=None) < now:
        return False
    return True


def get_device_license(db, device_id: str):
    """设备名下 active 未过期卡（一卡一机：一台设备最多一张生效卡）。
    用于绑定后台时回写归属 + 严格模式校验。无卡返回 None。
    """
    from models.license import License
    from sqlalchemy import or_
    now = datetime.utcnow()
    lic = (
        db.query(License)
        .filter(
            License.device_id == device_id,
            License.status == "active",
            or_(
                License.expires_at.is_(None),
                License.expires_at >= now,
            ),
        )
        .first()
    )
    return lic


def get_tenant_quota(db, api_id: str) -> dict:
    """计算租户配额与用量。

    返回 {device_limit, device_used, account_limit, account_used,
           card_count, licensed, plan}
    - device_limit：User override 优先，否则 = 名下有效卡张数
    - account_limit：User override 优先，否则 = Σ 每卡套餐 account_limit（或单卡特批值）
    - 无 User override 且无卡时，device_limit=0 / account_limit=0（严格模式拒绝）
    """
    from models.license import License
    from models.device import DeviceBinding
    from models.account import Account
    from models.user import User

    # 1) 名下有效卡
    cards = (
        db.query(License)
        .filter(License.api_id == api_id, License.status == "active")
        .all()
    )
    cards = [c for c in cards if _is_effective(c)]
    now = datetime.utcnow()

    # 2) 卡配额聚合（单卡特批值优先，NULL=按套餐默认）
    from routers.licenses import PLAN_QUOTA
    card_device_limit = len(cards)  # 一卡一机：设备配额 = 卡张数
    card_account_limit = 0
    for c in cards:
        per_card = c.account_limit
        if per_card is None:
            per_card = PLAN_QUOTA.get(c.plan, {}).get("account_limit", 0)
        card_account_limit += per_card

    # 3) User override（管理员直接设的租户上限，优先于卡）
    user = db.query(User).filter(User.api_id == api_id).first()
    device_limit = card_device_limit
    account_limit = card_account_limit
    if user:
        if user.device_limit is not None:
            device_limit = user.device_limit
        if user.account_limit is not None:
            account_limit = user.account_limit

    # 4) 用量
    device_used = (
        db.query(DeviceBinding)
        .filter(DeviceBinding.api_id == api_id)
        .count()
    )
    account_used = (
        db.query(Account)
        .filter(Account.api_id == api_id)
        .count()
    )

    return {
        "device_limit": device_limit,
        "device_used": device_used,
        "account_limit": account_limit,
        "account_used": account_used,
        "card_count": len(cards),
        "licensed": len(cards) > 0,
        "plan": cards[0].plan if cards else "",
    }


def ensure_device_bindable(db, device_id: str, api_id: str):
    """设备绑定后台前的严格校验 + 归属回写。

    - 该设备名下必须有一张 active 未过期卡（无卡 → 403 未激活）
    - 把该卡 api_id 回写为设备上报的租户（卡密→设备→租户三环闭合）
    - 租户设备配额不足（User override 场景）→ 403 超限
    """
    lic = get_device_license(db, device_id)
    if not lic:
        raise HTTPException(
            status_code=403,
            detail="设备未激活卡密，请先输入卡密",
        )

    # 先回写归属：卡归到设备绑定的租户（首绑才调，幂等）
    # 必须先回写再算配额 —— 这张卡本身就是本设备的配额来源（一卡一机）
    if lic.api_id != api_id:
        lic.api_id = api_id
        logger.info(f"License {lic.key} claimed by tenant {api_id} via device {device_id}")

    # 回写后：本设备对应这张卡，设备数应恰好 ≤ 卡张数。
    # 若 admin 设了 User override 更小，则超限拒绝（设备已有归属，不重复占额）。
    quota = get_tenant_quota(db, api_id)
    if quota["device_used"] > quota["device_limit"]:
        raise HTTPException(
            status_code=403,
            detail=f"设备配额已用尽（{quota['device_used']}/{quota['device_limit']}）",
        )
    return lic


def ensure_account_importable(db, api_id: str, extra: int = 0, current_user=None):
    """账号导入前的配额校验。admin 跳过（全局共享账号不归属租户）。

    extra: 本次要导入的账号数。
    """
    if current_user and current_user.role == "admin":
        return True
    quota = get_tenant_quota(db, api_id)
    if not quota["licensed"]:
        raise HTTPException(
            status_code=403,
            detail="租户未激活卡密，请先输入卡密",
        )
    if quota["account_used"] + extra > quota["account_limit"]:
        raise HTTPException(
            status_code=403,
            detail=(
                f"账号配额不足（{quota['account_used']}/{quota['account_limit']}，"
                f"本次需 {extra}）"
            ),
        )
    return True
