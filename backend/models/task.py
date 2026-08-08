from sqlalchemy import Column, Integer, String, DateTime, Text
from sqlalchemy.sql import func
from database import Base

class Task(Base):
    """统一任务引擎的任务记录

    - 简单任务（旧前端）：type/target/device/account/progress
    - 引擎任务：config(JSON) + total/done/fail_count/last_log + 调度字段
    - 状态流转: pending -> running -> done | stopped | failed
    """
    __tablename__ = "tasks"

    id = Column(Integer, primary_key=True, index=True)
    api_id = Column(String(20), default="", index=True)   # 租户（关联用户）
    name = Column(String(200))
    type = Column(String(50), nullable=False)
    status = Column(String(20), default="pending")
    target = Column(Text)
    device = Column(String(100))
    account = Column(String(100))
    progress = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    finished_at = Column(DateTime(timezone=True))

    # ---- 统一任务引擎字段 ----
    config = Column(Text, default="{}")          # JSON 引擎配置
    total = Column(Integer, default=0)           # 总单元数
    done = Column(Integer, default=0)            # 已下发单元数
    fail_count = Column(Integer, default=0)      # 失败单元数
    last_log = Column(Text, default="")          # 最近进度日志
    error = Column(Text, default="")             # 错误信息
    started_at = Column(DateTime(timezone=True))
    next_dispatch_at = Column(DateTime(timezone=True))
