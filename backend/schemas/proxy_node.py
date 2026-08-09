from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class ProxyNodeResponse(BaseModel):
    id: int
    name: Optional[str] = ""
    country: Optional[str] = ""
    protocol: Optional[str] = ""
    address: Optional[str] = ""
    port: Optional[int] = 0
    config: Optional[str] = ""
    remark: Optional[str] = ""
    enabled: Optional[bool] = True
    created_at: Optional[datetime] = None
    class Config:
        from_attributes = True


class ProxyNodeCreate(BaseModel):
    name: str
    country: str = ""
    protocol: str = ""
    address: str = ""
    port: int = 0
    config: str = ""
    remark: str = ""
    enabled: bool = True


class ProxyNodeUpdate(BaseModel):
    name: Optional[str] = None
    country: Optional[str] = None
    protocol: Optional[str] = None
    address: Optional[str] = None
    port: Optional[int] = None
    config: Optional[str] = None
    remark: Optional[str] = None
    enabled: Optional[bool] = None


class ProxyNodeImportRequest(BaseModel):
    """订阅链接/内容批量导入"""
    subscription: str
    default_country: str = ""
    remark: str = ""
