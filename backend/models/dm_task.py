from sqlalchemy import Column, Integer, String, Text, DateTime
from sqlalchemy.sql import func
from database import Base


class DmTask(Base):
    """自动私信任务（自动私信）"""
    __tablename__ = "dm_tasks"

    id = Column(Integer, primary_key=True, index=True)
    device_id = Column(String(100), index=True)          # 设备机器码
    target_username = Column(String(200), default="")    # 私信目标用户名（空 = 走消息页）
    content = Column(Text, default="")                   # 私信内容 / 话术
    status = Column(String(20), default="pending")       # pending/processing/done/failed
    scheduled_at = Column(DateTime(timezone=True))       # 计划发送时间
    api_id = Column(String(64), default="", index=True)  # 租户
    result = Column(Text, default="")                    # 执行结果
    created_at = Column(DateTime(timezone=True), server_default=func.now())
