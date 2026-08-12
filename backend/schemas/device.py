from pydantic import BaseModel, field_validator
from typing import Optional, List, Any, Union
from datetime import datetime
import json

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
    current_account_id: Optional[int] = 0
    group_name: Optional[str] = "未分组"
    added_by: Optional[str] = "系统"
    tags: Optional[List[str]] = []
    api_id: Optional[Union[str, int]] = ""
    last_seen: Optional[datetime] = None
    last_online: Optional[datetime] = None
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True

    @field_validator("tags", mode="before")
    @classmethod
    def parse_tags(cls, v):
        if isinstance(v, str):
            try:
                return json.loads(v)
            except (json.JSONDecodeError, TypeError):
                return []
        return v or []

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
