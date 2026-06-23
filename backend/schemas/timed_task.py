from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class TimedTaskResponse(BaseModel):
    id: int
    name: str
    cron: str
    task_type: Optional[str] = ""
    enabled: bool = True
    last_run: Optional[str] = None
    next_run: Optional[str] = None

    class Config:
        from_attributes = True

class TimedTaskCreateRequest(BaseModel):
    name: str
    cron: str
    task_type: Optional[str] = "数据采集"

class TimedTaskUpdateRequest(BaseModel):
    name: Optional[str] = None
    cron: Optional[str] = None
    task_type: Optional[str] = None
    enabled: Optional[bool] = None
