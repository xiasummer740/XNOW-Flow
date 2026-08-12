from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


class PublicUserResponse(BaseModel):
    id: int
    aweme_id: Optional[str] = ""
    nickname: Optional[str] = ""
    avatar_url: Optional[str] = ""
    gender: Optional[str] = ""
    country: Optional[str] = ""
    followers: Optional[int] = 0
    following_count: Optional[int] = 0
    age: Optional[int] = 0
    videos_count: Optional[int] = 0
    signature: Optional[str] = ""
    keyword: Optional[str] = ""
    ai_tagged: Optional[int] = 0
    created_at: Optional[datetime] = None
    class Config:
        from_attributes = True


class PublicFeedRequest(BaseModel):
    """从当前租户采集数据投喂公共库的筛选条件"""
    source_types: Optional[List[str]] = None      # 只投喂指定采集类型
    group_names: Optional[List[str]] = None       # 只投喂指定分组
    min_followers: Optional[int] = None           # 粉丝数下限
    require_avatar: Optional[bool] = True         # 必须有头像（供 AI 打标）
    max_count: Optional[int] = 500                # 单次投喂上限


class PublicCopyRequest(BaseModel):
    """把公共库记录复制到当前租户采集数据"""
    ids: List[int]
    group_name: str = "未分组"


class PublicTagRequest(BaseModel):
    """AI 头像打标批处理"""
    limit: Optional[int] = 10
