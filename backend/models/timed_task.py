from sqlalchemy import Column, Integer, String, Boolean, DateTime, Text
from sqlalchemy.sql import func
from database import Base

class TimedTask(Base):
    __tablename__ = "timed_tasks"

    id = Column(Integer, primary_key=True, index=True)
    api_id = Column(String(20), default="", index=True)   # 租户（关联用户）
    name = Column(String(200), nullable=False)
    cron = Column(String(50), nullable=False)
    task_type = Column(String(50), default="数据采集")
    device_ids = Column(Text, default="[]")     # 目标设备 JSON 数组
    action = Column(String(50), default="")      # 指令动作
    params = Column(Text, default="{}")          # 指令参数 JSON
    enabled = Column(Boolean, default=True)
    last_run = Column(DateTime(timezone=True))
    next_run = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
