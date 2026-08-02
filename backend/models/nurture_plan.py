from sqlalchemy import Column, Integer, String, Text, DateTime
from sqlalchemy.sql import func
from database import Base


class NurturePlan(Base):
    """养号计划（批量自动养号引擎）

    daily_actions: JSON 字符串，形如
    {
        "min_scrolls": 2,
        "max_scrolls": 5,
        "like_probability": 0.2,
        "follow_probability": 0.05,
        "comment_probability": 0.02,
        "browse_minutes": 2
    }
    device_ids: JSON 数组（设备机器码 / DeviceBinding.name）
    account_ids: JSON 数组（账号 id）
    """
    __tablename__ = "nurture_plans"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(200), nullable=False, default="")     # 计划名称
    device_ids = Column(Text, default="[]")                    # JSON array
    account_ids = Column(Text, default="[]")                   # JSON array
    daily_actions = Column(Text, default="{}")                 # JSON object
    status = Column(String(20), default="paused")              # active/paused/completed
    start_date = Column(DateTime(timezone=True))               # 计划开始时间
    end_date = Column(DateTime(timezone=True))                 # 计划结束时间
    api_id = Column(String(64), default="", index=True)        # 租户
    created_at = Column(DateTime(timezone=True), server_default=func.now())
