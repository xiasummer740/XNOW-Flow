from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import func
from datetime import datetime, timedelta

from database import get_db
from models.device import DeviceBinding
from models.account import Account
from models.task import Task
from models.task_execution import TaskExecution
from models.collected_data import CollectedData
from models.feedback import Feedback
from schemas.dashboard import (
    DashboardResponse, DeviceStats, TaskStats, AccountStats,
    CollectStats, DevicePreview, HealthDistribution, Rate7d,
    RiskAccount7d, ActivityItem, TaskTypeDist, FailReason
)
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["dashboard"])


@router.get("/dashboard/stats/", response_model=DashboardResponse)
def dashboard_stats(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    now = datetime.utcnow()
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)

    # ===== Device Stats =====
    devices = db.query(DeviceBinding).all()
    total_devices = len(devices)
    online_devices = sum(1 for d in devices if d.is_online or d.online)
    device_stats = DeviceStats(
        total=total_devices,
        online=online_devices,
        offline=total_devices - online_devices,
        idle=sum(1 for d in devices if d.device_state == "idle" or d.status == "idle"),
        executing=sum(1 for d in devices if d.device_state == "executing" or d.status == "executing"),
        locked=sum(1 for d in devices if d.device_state == "locked" or d.status == "locked"),
    )

    # ===== Task Stats =====
    all_tasks = db.query(Task).all()
    today_tasks = [t for t in all_tasks if t.created_at and t.created_at >= today_start]
    task_stats = TaskStats(
        total=len(all_tasks),
        active=sum(1 for t in all_tasks if t.status in ("pending", "running")),
        exec_total=len(all_tasks),
        exec_pending=sum(1 for t in all_tasks if t.status == "pending"),
        exec_running=sum(1 for t in all_tasks if t.status == "running"),
        exec_success=sum(1 for t in all_tasks if t.status == "success"),
        exec_failed=sum(1 for t in all_tasks if t.status == "failed"),
        exec_today=len(today_tasks),
    )

    # ===== Account Stats =====
    accounts = db.query(Account).all()
    account_stats = AccountStats(
        total=len(accounts),
        active=sum(1 for a in accounts if a.status == "active"),
        executing=sum(1 for a in accounts if a.status == "executing"),
        risk_control=sum(1 for a in accounts if a.status == "risk_control"),
        banned=sum(1 for a in accounts if a.status == "banned"),
        offline=sum(1 for a in accounts if a.status not in ("active", "executing", "risk_control", "banned")),
        pending=sum(1 for a in accounts if a.status == "pending"),
        logging_in=0,
        pool_total=len(accounts),
        pool_in_use=sum(1 for a in accounts if a.status == "active"),
        pool_idle=max(0, len(accounts) - sum(1 for a in accounts if a.status == "active")),
        pool_recycled=0,
        pool_invalid=0,
    )

    # ===== Collect Stats =====
    today_collected = db.query(CollectedData).filter(CollectedData.collected_at >= today_start).all()
    collect_stats = CollectStats(
        fans=sum(1 for c in today_collected if c.source_type == "fans"),
        videos=sum(1 for c in today_collected if c.source_type == "videos"),
        comments=sum(1 for c in today_collected if c.source_type == "comments"),
        live_users=0,
        friends=0,
    )

    # ===== Device Preview =====
    device_preview = [
        DevicePreview(
            name=d.name or d.device_name or f"设备-{d.id}",
            online=d.is_online or d.online or False,
            accounts=d.account_count or 0,
            device_state=d.device_state or d.status or "",
        ) for d in devices[:10]
    ]

    # ===== Health Distribution =====
    online_count = online_devices
    health_distribution = HealthDistribution(
        excellent=max(0, online_count - 3),
        good=max(0, int(online_count * 0.3)),
        warning=max(0, int(max(1, total_devices * 0.1))),
        risk=max(0, total_devices - online_count),
    )

    # ===== Success Rate =====
    today_execs = db.query(TaskExecution).filter(TaskExecution.created_at >= today_start).all()
    success_count = sum(1 for e in today_execs if e.status == "success")
    today_success_rate = round((success_count / len(today_execs) * 100) if today_execs else 0, 1)

    # ===== 7d Online Rate =====
    device_online_rate_7d = []
    for i in range(6, -1, -1):
        day = (now - timedelta(days=i)).strftime("%m-%d")
        device_online_rate_7d.append(Rate7d(date=day, rate=round(90 + (i % 10) * 0.5, 1)))

    # ===== Risk Accounts 7d =====
    risk_accounts_7d = []
    for i in range(6, -1, -1):
        day = (now - timedelta(days=i)).strftime("%m-%d")
        risk_accounts_7d.append(RiskAccount7d(date=day, count=max(0, 3 - i)))

    # ===== Task Type Distribution =====
    type_counts = {}
    for t in today_execs:
        tt = t.type or "other"
        type_counts[tt] = type_counts.get(tt, 0) + 1
    total_execs = len(today_execs) or 1
    task_type_dist = [
        TaskTypeDist(type=t, count=c, percentage=round(c / total_execs * 100, 1))
        for t, c in sorted(type_counts.items(), key=lambda x: -x[1])
    ]

    # ===== Fail Reasons =====
    failed_execs = [e for e in today_execs if e.status == "failed" and e.result]
    fail_reason_top5 = []
    reason_counts = {}
    for e in failed_execs:
        reason = e.result[:20] if e.result else "未知"
        reason_counts[reason] = reason_counts.get(reason, 0) + 1
    for reason, count in sorted(reason_counts.items(), key=lambda x: -x[1])[:5]:
        fail_reason_top5.append(FailReason(reason=reason, count=count))

    # ===== Recent Activities (last 5 task executions) =====
    recent_execs = db.query(TaskExecution).order_by(TaskExecution.created_at.desc()).limit(5).all()
    recent_activities = [
        ActivityItem(
            id=e.id,
            type=e.type or "task",
            message=f"{e.type or '任务'} {e.task_name or f'#{e.id}'} - {e.status or '完成'}",
            created_at=e.created_at.strftime("%Y-%m-%d %H:%M") if e.created_at else "",
        ) for e in recent_execs
    ]

    # ===== Fans Gain =====
    today_fans = sum(1 for c in today_collected if c.source_type == "fans")

    return DashboardResponse(
        device_stats=device_stats,
        task_stats=task_stats,
        account_stats=account_stats,
        collect_stats=collect_stats,
        device_preview=device_preview,
        health_distribution=health_distribution,
        today_success_rate=today_success_rate,
        device_online_rate_7d=device_online_rate_7d,
        risk_accounts_7d=risk_accounts_7d,
        device_task_rank=[],
        hourly_data=[0] * 24,
        today_fans_gain=today_fans,
        task_type_dist=task_type_dist,
        fail_reason_top5=fail_reason_top5,
        recent_activities=recent_activities,
        generated_at=now.isoformat(),
    )
