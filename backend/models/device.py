from sqlalchemy import Column, Integer, String, DateTime, func

from database import Base


class DeviceBinding(Base):
    __tablename__ = "device_bindings"

    id = Column(Integer, primary_key=True, index=True)
    device_id = Column(String(100), unique=True, nullable=False)
    device_name = Column(String(100))
    status = Column(String(20), default="offline")
    last_active = Column(DateTime, nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
