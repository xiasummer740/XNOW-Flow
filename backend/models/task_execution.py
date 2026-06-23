from sqlalchemy import Column, Integer, String, DateTime, func

from database import Base


class TaskExecution(Base):
    __tablename__ = "task_executions"

    id = Column(Integer, primary_key=True, index=True)
    task_id = Column(Integer, nullable=False)
    status = Column(String(20), default="running")
    started_at = Column(DateTime, server_default=func.now())
    finished_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, server_default=func.now())
