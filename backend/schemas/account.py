from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class AccountResponse(BaseModel):
    id: int
    nickname: Optional[str] = ""
    username: Optional[str] = ""
    tk_number: Optional[str] = ""
    unique_id: Optional[str] = ""
    followers: Optional[int] = 0
    following_count: Optional[int] = 0
    video_count: Optional[int] = 0
    status: Optional[str] = ""
    region: Optional[str] = ""
    country: Optional[str] = ""

    class Config:
        from_attributes = True
