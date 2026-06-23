from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class FeedbackResponse(BaseModel):
    id: int
    title: Optional[str] = ""
    content: Optional[str] = ""
    contact: Optional[str] = ""
    status: Optional[str] = ""
    reply: Optional[str] = None
    created_at: Optional[datetime] = None
    class Config: from_attributes = True

class FeedbackCreateRequest(BaseModel):
    title: str
    content: str
    contact: Optional[str] = ""
