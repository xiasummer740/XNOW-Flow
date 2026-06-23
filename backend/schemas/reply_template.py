from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class ReplyTemplateResponse(BaseModel):
    id: int
    name: str
    content: Optional[str] = ""
    match_type: Optional[str] = "keyword"
    match_rule: Optional[str] = ""
    is_active: Optional[bool] = True
    created_at: Optional[datetime] = None
    class Config: from_attributes = True

class ReplyTemplateCreateRequest(BaseModel):
    name: str
    content: str
    match_type: Optional[str] = "keyword"
    match_rule: Optional[str] = ""

class ReplyTemplateUpdateRequest(BaseModel):
    name: Optional[str] = None
    content: Optional[str] = None
    match_type: Optional[str] = None
    match_rule: Optional[str] = None
    is_active: Optional[bool] = None
