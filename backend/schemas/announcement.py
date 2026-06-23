from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class AnnouncementResponse(BaseModel):
    id: int
    title: str
    content: Optional[str] = ""
    priority: Optional[str] = "normal"
    is_pinned: Optional[bool] = False
    is_active: Optional[bool] = True
    created_at: Optional[datetime] = None
    class Config: from_attributes = True
