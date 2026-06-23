from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class MediaResponse(BaseModel):
    id: int
    filename: Optional[str] = ""
    original_name: Optional[str] = ""
    file_type: Optional[str] = ""
    file_size: Optional[int] = 0
    url: Optional[str] = ""
    created_at: Optional[datetime] = None
    class Config: from_attributes = True
