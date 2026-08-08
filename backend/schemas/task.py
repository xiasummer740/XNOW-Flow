from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from datetime import datetime


class TaskResponse(BaseModel):
    id: int
    name: Optional[str] = ""
    type: Optional[str] = ""
    status: Optional[str] = ""
    target: Optional[str] = ""
    device: Optional[str] = ""
    account: Optional[str] = ""
    progress: Optional[int] = 0
    created_at: Optional[datetime] = None
    finished_at: Optional[datetime] = None

    # 统一任务引擎字段
    config: Optional[Dict[str, Any]] = {}
    total: Optional[int] = 0
    done: Optional[int] = 0
    fail_count: Optional[int] = 0
    last_log: Optional[str] = ""
    error: Optional[str] = ""
    started_at: Optional[datetime] = None
    next_dispatch_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class TaskCreateRequest(BaseModel):
    """统一任务引擎创建请求

    兼容旧前端：只填 type/target/device/account/count 也创建（引擎按简单任务处理，
    无 targets 时不进引擎，仅记录）。
    """
    type: str
    target: Optional[str] = ""
    device: Optional[str] = ""
    account: Optional[str] = ""
    count: Optional[str] = "10"
    # 引擎配置（统一任务引擎）
    name: Optional[str] = ""
    config: Optional[Dict[str, Any]] = {}


class TaskStartRequest(BaseModel):
    """启动引擎任务前的目标解析选项"""
    target_group: Optional[str] = ""   # 从采集数据分组解析 targets（数据组引用）
    count: Optional[int] = 0           # 0=len(targets)
