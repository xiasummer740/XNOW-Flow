from sqlalchemy import Column, Integer, String, DateTime, Boolean
from sqlalchemy.sql import func
from database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, index=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    role = Column(String(20), default="user")  # admin / user
    is_active = Column(Boolean, default=True)
    api_id = Column(String(64), unique=True, default=None)  # API标识符
    # 配额覆盖：NULL=按名下卡密套餐算；非 NULL=管理员直接设的租户上限
    device_limit = Column(Integer, nullable=True)
    account_limit = Column(Integer, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
