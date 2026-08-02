from sqlalchemy import Column, Integer, String, DateTime, Text
from sqlalchemy.sql import func
from database import Base


class UDIDRequest(Base):
    """UDID 签名申请 — 用户提交 UDID，管理员签名后提供下载"""
    __tablename__ = "udid_requests"

    id = Column(Integer, primary_key=True, index=True)
    udid = Column(String(100), index=True)          # 用户手机 UDID
    device_name = Column(String(100), default="")   # 设备名称（如 iPhone 13）
    email = Column(String(100), default="")          # 联系方式
    status = Column(String(20), default="pending")   # pending/signed/rejected
    ipa_url = Column(Text, default="")                # 签名后的 IPA 下载链接
    admin_note = Column(String(200), default="")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    signed_at = Column(DateTime(timezone=True))
