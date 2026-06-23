from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class DeviceResponse(BaseModel):
    id: int
    name: Optional[str] = ""
    device_name: Optional[str] = ""
    status: Optional[str] = ""
    online: Optional[bool] = False
    account_count: Optional[int] = 0
    last_online: Optional[datetime] = None
    app_version: Optional[str] = ""

    class Config:
        from_attributes = True
