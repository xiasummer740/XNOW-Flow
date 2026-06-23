from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class TaskExecutionResponse(BaseModel):
    id: int
    task_name: Optional[str] = ""
    type: Optional[str] = ""
    status: Optional[str] = ""
    device: Optional[str] = ""
    account: Optional[str] = ""
    target: Optional[str] = ""
    result: Optional[str] = ""
    started_at: Optional[datetime] = None
    finished_at: Optional[datetime] = None
    duration: Optional[float] = 0

    class Config:
        from_attributes = True
