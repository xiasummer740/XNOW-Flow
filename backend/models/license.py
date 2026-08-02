from sqlalchemy import Column, Integer, String, DateTime, Boolean, Text
from sqlalchemy.sql import func
from database import Base


class License(Base):
    """卡密授权 — 用户输入密钥激活设备（1年），绑定 UDID/device_id"""
    __tablename__ = "licenses"

    id = Column(Integer, primary_key=True, index=True)
    key = Column(String(32), unique=True, index=True)   # 卡密（如 XXXX-XXXX-XXXX-XXXX）
    plan = Column(String(30), default="year1")           # 套餐：year1=1年
    status = Column(String(20), default="unused")        # unused/active/expired/disabled
    device_id = Column(String(100), default="")           # 绑定的设备ID
    udid = Column(String(100), default="")                # 绑定的苹果UDID
    api_id = Column(String(20), default="", index=True)   # 绑定后台租户
    activated_at = Column(DateTime(timezone=True))        # 激活时间
    expires_at = Column(DateTime(timezone=True))          # 到期时间
    remark = Column(String(200), default="")              # 备注（客户名等）
    # 配额：NULL=按套餐默认（PLAN_QUOTA），非 NULL=管理员特批单卡
    device_limit = Column(Integer, nullable=True)
    account_limit = Column(Integer, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
