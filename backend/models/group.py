from sqlalchemy import Column, Integer, String, DateTime
from sqlalchemy.sql import func
from database import Base

class DeviceGroup(Base):
    __tablename__ = "device_groups"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), unique=True, nullable=False)  # 分组名称
    description = Column(String(255), default="")
    device_count = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
