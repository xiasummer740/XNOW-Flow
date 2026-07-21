from pydantic import BaseModel, field_validator
from typing import Optional, List
from datetime import datetime
import json

class AccountImportRequest(BaseModel):
    """单条账号导入"""
    nickname: Optional[str] = ""
    username: Optional[str] = ""
    aweme_id: Optional[str] = ""
    aweme_number: Optional[str] = ""
    password: Optional[str] = ""
    cookies: Optional[str] = ""
    token: Optional[str] = ""
    phone: Optional[str] = ""
    email: Optional[str] = ""
    has_2fa: Optional[bool] = False
    region: Optional[str] = ""
    country: Optional[str] = ""
    act_country: Optional[str] = ""
    act_language: Optional[str] = ""
    act_city: Optional[str] = ""
    act_sex: Optional[int] = 0
    act_age: Optional[int] = 0
    signature: Optional[str] = ""
    followers: Optional[int] = 0
    fans_count: Optional[int] = 0
    following_count: Optional[int] = 0
    digg_count: Optional[int] = 0
    video_count: Optional[int] = 0
    friends_count: Optional[int] = 0
    diamond: Optional[int] = 0
    health_score: Optional[int] = 100
    avatar_url: Optional[str] = ""
    web_url: Optional[str] = ""
    bundle_id: Optional[str] = ""
    register_time: Optional[int] = 0
    tags: Optional[str] = "[]"
    remark: Optional[str] = ""
    device_id: Optional[str] = ""
    source: Optional[str] = "manual_import"

    def to_orm_dict(self) -> dict:
        """转成 ORM 可接受的 dict，credentials 合并 password/cookies/token"""
        d = self.model_dump(exclude={"password", "cookies", "token"})
        # 空字符串唯一约束冲突 → 转 None（SQLite 允许多个 NULL）
        for key in ("aweme_id", "aweme_number", "unique_id"):
            if d.get(key) == "":
                d[key] = None
        creds = {}
        if self.password: creds["password"] = self.password
        if self.cookies: creds["cookies"] = self.cookies
        if self.token: creds["token"] = self.token
        d["credentials"] = json.dumps(creds, ensure_ascii=False)
        return d


class AccountBatchImportRequest(BaseModel):
    """批量导入"""
    accounts: List[AccountImportRequest]


class AccountDispatchRequest(BaseModel):
    """分配账号到设备"""
    account_ids: List[int]
    device_id: str


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
    has_credentials: Optional[bool] = False
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

    @staticmethod
    def from_orm_with_creds(account) -> "AccountResponse":
        """从 ORM 对象构建，自动计算 has_credentials"""
        resp = AccountResponse.model_validate(account)
        try:
            creds = json.loads(account.credentials or "{}")
            resp.has_credentials = bool(creds.get("password") or creds.get("cookies") or creds.get("token"))
        except (json.JSONDecodeError, TypeError):
            resp.has_credentials = False
        return resp
