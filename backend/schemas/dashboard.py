from pydantic import BaseModel
from typing import List, Optional, Any
from datetime import datetime

class DeviceStats(BaseModel):
    total: int
    online: int
    offline: int
    idle: int
    executing: int
    locked: int

class TaskStats(BaseModel):
    total: int = 0
    active: int = 0
    exec_total: int = 0
    exec_pending: int = 0
    exec_running: int = 0
    exec_success: int = 0
    exec_failed: int = 0
    exec_today: int = 0

class AccountStats(BaseModel):
    total: int = 0
    active: int = 0
    executing: int = 0
    risk_control: int = 0
    banned: int = 0
    offline: int = 0
    pending: int = 0
    logging_in: int = 0
    pool_total: int = 0
    pool_in_use: int = 0
    pool_idle: int = 0
    pool_recycled: int = 0
    pool_invalid: int = 0

class CollectStats(BaseModel):
    fans: int = 0
    videos: int = 0
    comments: int = 0
    live_users: int = 0
    friends: int = 0

class DevicePreview(BaseModel):
    name: Optional[str] = ""
    online: bool = False
    accounts: Optional[int] = 0
    device_state: Optional[str] = ""

class HealthDistribution(BaseModel):
    excellent: int = 0
    good: int = 0
    warning: int = 0
    risk: int = 0

class Rate7d(BaseModel):
    date: str
    rate: float

class RiskAccount7d(BaseModel):
    date: str
    count: int

class ActivityItem(BaseModel):
    id: int
    type: str
    message: str
    created_at: str

class TaskTypeDist(BaseModel):
    type: str
    count: int
    percentage: float

class FailReason(BaseModel):
    reason: str
    count: int

class DashboardResponse(BaseModel):
    device_stats: DeviceStats
    task_stats: TaskStats
    account_stats: AccountStats
    collect_stats: CollectStats
    system_stats: Optional[Any] = None
    device_preview: List[DevicePreview]
    health_distribution: HealthDistribution
    today_success_rate: float
    device_online_rate_7d: List[Rate7d]
    risk_accounts_7d: List[RiskAccount7d] = []
    device_task_rank: List = []
    hourly_data: List[int] = []
    today_fans_gain: int = 0
    task_type_dist: List[TaskTypeDist] = []
    fail_reason_top5: List[FailReason] = []
    recent_activities: List[ActivityItem] = []
    generated_at: str = ""
