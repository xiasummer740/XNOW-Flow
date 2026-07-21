from pydantic import BaseModel, field_validator
from typing import Optional, List
from datetime import datetime
import json

class AccountResponse(BaseModel):
    id: int
    nickname: Optional[str] = ""
    username: Optional[str] = ""
    aweme_id: Optional[str] = ""
    aweme_number: Optional[str] = ""
    unique_id: Optional[str] = ""
    avatar_url: Optional[str] = ""
    followers: Optional[int] = 0
    fans_count: Optional[int] = 0
    following_count: Optional[int] = 0
    digg_count: Optional[int] = 0
    video_count: Optional[int] = 0
    friends_count: Optional[int] = 0
    diamond: Optional[int] = 0
    health_score: Optional[int] = 100
    signature: Optional[str] = ""
    web_url: Optional[str] = ""
    status: Optional[str] = ""
    device_id: Optional[str] = ""
    bundle_id: Optional[str] = ""
    region: Optional[str] = ""
    country: Optional[str] = ""
    act_country: Optional[str] = ""
    act_language: Optional[str] = ""
    act_city: Optional[str] = ""
    act_sex: Optional[int] = 0
    act_age: Optional[int] = 0
    phone: Optional[str] = ""
    email: Optional[str] = ""
    has_2fa: Optional[bool] = False
    is_email_bound: Optional[bool] = False
    is_phone_bound: Optional[bool] = False
    tags: Optional[List[str]] = []
    remark: Optional[str] = ""
    register_time: Optional[int] = 0
    source: Optional[str] = "auto"
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
