from sqlalchemy import Column, Integer, String, Boolean, DateTime
from sqlalchemy.sql import func
from database import Base

class DeviceBinding(Base):
    __tablename__ = "device_bindings"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    device_name = Column(String(100))
    status = Column(String(20), default="idle")
    online = Column(Boolean, default=False)
    account_count = Column(Integer, default=0)
    accounts = Column(Integer, default=0)
    last_online = Column(DateTime(timezone=True))
    app_version = Column(String(50))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
