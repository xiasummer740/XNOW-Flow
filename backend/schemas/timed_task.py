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
    device_ids: Optional[list] = None   # 目标设备机器码
    action: Optional[str] = ""          # 指令动作
    params: Optional[dict] = None       # 指令参数

class TimedTaskUpdateRequest(BaseModel):
    name: Optional[str] = None
    cron: Optional[str] = None
    task_type: Optional[str] = None
    enabled: Optional[bool] = None
    device_ids: Optional[list] = None
    action: Optional[str] = None
    params: Optional[dict] = None
