from pydantic import BaseModel
from typing import Optional, List, Any
from datetime import datetime

class DeviceResponse(BaseModel):
    id: int
    name: Optional[str] = ""
    device_name: Optional[str] = ""
    device_id: Optional[str] = ""
    mobile_no: Optional[str] = ""
    is_online: Optional[bool] = False
    device_state: Optional[str] = "offline"
    status: Optional[str] = "offline"
    online: Optional[bool] = False
    lock_reason: Optional[str] = ""
    bundle_id: Optional[str] = ""
    app_version: Optional[str] = ""
    account_count: Optional[int] = 0
    max_accounts: Optional[int] = 20
    daily_task_count: Optional[int] = 0
    current_task: Optional[str] = None
    group_name: Optional[str] = "未分组"
    tags: Optional[List[str]] = []
    api_id: Optional[int] = 0
    last_seen: Optional[datetime] = None
    last_online: Optional[datetime] = None
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True

class DeviceGroupResponse(BaseModel):
    id: int
    name: str
    description: str = ""
    device_count: int = 0
    created_at: Optional[datetime] = None
    class Config: from_attributes = True

class DeviceGroupCreate(BaseModel):
    name: str
    description: Optional[str] = ""

class BatchGroupRequest(BaseModel):
    device_ids: List[int]
    group_name: str

class BatchDeleteRequest(BaseModel):
    device_ids: List[int]

class DispatchTaskRequest(BaseModel):
    device_ids: List[int]
    action: str  # scroll_down, scroll_up, screenshot, etc.
    params: Optional[dict] = {}
