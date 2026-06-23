from pydantic import BaseModel
from typing import List, Optional

class DeviceStats(BaseModel):
    total: int
    online: int
    offline: int
    idle: int
    executing: int
    locked: int

class TaskStats(BaseModel):
    exec_today: int
    exec_success: int
    exec_failed: int

class AccountStats(BaseModel):
    total: int
    active: int
    risk_control: int
    banned: int
    pool_total: int
    pool_in_use: int

class CollectStats(BaseModel):
    fans: int
    videos: int
    comments: int

class DevicePreview(BaseModel):
    name: Optional[str] = ""
    online: bool
    accounts: Optional[int] = 0
    device_state: Optional[str] = ""

class HealthDistribution(BaseModel):
    excellent: int
    good: int
    warning: int
    risk: int

class Rate7d(BaseModel):
    date: str
    rate: float

class DashboardResponse(BaseModel):
    device_stats: DeviceStats
    task_stats: TaskStats
    account_stats: AccountStats
    collect_stats: CollectStats
    device_preview: List[DevicePreview]
    health_distribution: HealthDistribution
    today_success_rate: float
    device_online_rate_7d: List[Rate7d]
    device_task_rank: list = []
    hourly_data: List[int]
    today_fans_gain: int
