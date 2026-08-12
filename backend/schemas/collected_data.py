from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

class CollectedDataResponse(BaseModel):
    id: int
    source: Optional[str] = ""
    source_type: Optional[str] = ""
    content: Optional[str] = ""
    author: Optional[str] = ""
    url: Optional[str] = ""
    gender: Optional[str] = ""
    region: Optional[str] = ""
    followers: Optional[int] = 0
    following_count: Optional[int] = 0
    age: Optional[int] = 0
    aweme_id: Optional[str] = ""
    group_name: Optional[str] = "未分组"
    api_id: Optional[str] = ""
    remark: Optional[str] = ""
    collected_at: Optional[datetime] = None
    class Config: from_attributes = True

class CollectedDataItem(BaseModel):
    """单条采集数据（批量插入用）"""
    source: Optional[str] = "device"
    source_type: Optional[str] = "fans"
    content: Optional[str] = ""
    author: str = ""
    url: Optional[str] = ""
    gender: Optional[str] = ""
    region: Optional[str] = ""
    followers: Optional[int] = 0
    following_count: Optional[int] = 0
    age: Optional[int] = 0
    aweme_id: Optional[str] = ""
    group_name: Optional[str] = "未分组"
    remark: Optional[str] = ""
    dedupe_key: Optional[str] = ""

class CollectedDataBatchInsert(BaseModel):
    items: List[CollectedDataItem]

class GroupAssignRequest(BaseModel):
    group_name: str = "未分组"

class BatchGroupAssignRequest(BaseModel):
    ids: List[int]
    group_name: str = "未分组"
