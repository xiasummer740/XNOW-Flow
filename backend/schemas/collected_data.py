from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class CollectedDataResponse(BaseModel):
    id: int
    source: Optional[str] = ""
    source_type: Optional[str] = ""
    content: Optional[str] = ""
    author: Optional[str] = ""
    url: Optional[str] = ""
    collected_at: Optional[datetime] = None
    class Config: from_attributes = True
