from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class TaskResponse(BaseModel):
    id: int
    name: Optional[str] = ""
    type: Optional[str] = ""
    status: Optional[str] = ""
    target: Optional[str] = ""
    device: Optional[str] = ""
    account: Optional[str] = ""
    progress: Optional[int] = 0
    created_at: Optional[datetime] = None
    finished_at: Optional[datetime] = None

    class Config:
        from_attributes = True

class TaskCreateRequest(BaseModel):
    type: str
    target: str
    device: Optional[str] = ""
    account: Optional[str] = ""
    count: Optional[str] = "10"
