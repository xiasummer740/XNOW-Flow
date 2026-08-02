from sqlalchemy import Column, Integer, String, DateTime, Text, Float
from sqlalchemy.sql import func
from database import Base

class TaskExecution(Base):
    __tablename__ = "task_executions"

    id = Column(Integer, primary_key=True, index=True)
    api_id = Column(String(20), default="", index=True)   # 租户（关联用户）
    task_name = Column(String(200))
    type = Column(String(50))
    status = Column(String(20), default="pending")
    device = Column(String(100))
    account = Column(String(100))
    target = Column(Text)
    result = Column(Text)
    started_at = Column(DateTime(timezone=True))
    finished_at = Column(DateTime(timezone=True))
    duration = Column(Float, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
