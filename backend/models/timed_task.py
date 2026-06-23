from sqlalchemy import Column, Integer, String, DateTime, func

from database import Base


class TimedTask(Base):
    __tablename__ = "timed_tasks"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    cron_expr = Column(String(100), nullable=False)
    task_type = Column(String(50), nullable=False)
    status = Column(String(20), default="active")
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
