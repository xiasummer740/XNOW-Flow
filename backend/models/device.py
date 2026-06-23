from sqlalchemy import Column, Integer, String, Boolean, DateTime, Text
from sqlalchemy.sql import func
from database import Base

class DeviceBinding(Base):
    __tablename__ = "device_bindings"

    id = Column(Integer, primary_key=True, index=True)
    # Basic info
    name = Column(String(100), nullable=False)          # 设备名称（显示用）
    device_name = Column(String(100))                   # 设备型号
    device_id = Column(String(255), unique=True)        # 设备机器码 (18880bfa...)
    mobile_no = Column(String(50), default="")          # 手机号码
    # Status
    is_online = Column(Boolean, default=False)           # 在线状态
    device_state = Column(String(20), default="offline") # offline/online/idle/executing/locked
    status = Column(String(20), default="offline")      # 运行状态（向后兼容）
    online = Column(Boolean, default=False)             # 向后兼容
    lock_reason = Column(String(255), default="")       # 锁定原因
    # App info
    bundle_id = Column(String(100), default="")          # 包名
    app_version = Column(String(50), default="")        # 应用版本
    # Accounts
    account_count = Column(Integer, default=0)          # 已绑定账号数
    max_accounts = Column(Integer, default=20)          # 最大账号数
    # Tasks
    daily_task_count = Column(Integer, default=0)       # 今日任务数
    current_task = Column(String(255), default=None)    # 当前执行任务
    # Group
    group_name = Column(String(100), default="未分组")  # 所属分组
    tags = Column(Text, default="[]")                   # JSON tags
    # Meta
    api_id = Column(Integer, default=0)                  # API ID
    last_seen = Column(DateTime(timezone=True))          # 最后在线时间
    last_online = Column(DateTime(timezone=True))        # 向后兼容
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
