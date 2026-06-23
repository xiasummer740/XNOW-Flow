from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from datetime import datetime, timedelta

from database import get_db
from models.task_execution import TaskExecution
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["execution_stats"])


@router.get("/execution-stats/")
def execution_stats(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    today = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    days = []
    for i in range(6, -1, -1):
        day_start = today - timedelta(days=i)
        day_end = day_start + timedelta(days=1)
        execs = (
            db.query(TaskExecution)
            .filter(
                TaskExecution.created_at >= day_start,
                TaskExecution.created_at < day_end,
            )
            .all()
        )
        days.append(
            {
                "date": day_start.strftime("%m-%d"),
                "total": len(execs),
                "success": sum(1 for e in execs if e.status == "success"),
                "failed": sum(1 for e in execs if e.status == "failed"),
                "devices": len(set(e.device for e in execs if e.device)),
            }
        )

    all_execs = db.query(TaskExecution).all()
    type_map = {}
    for e in all_execs:
        t = e.type or "other"
        if t not in type_map:
            type_map[t] = {"type": t, "count": 0, "success": 0}
        type_map[t]["count"] += 1
        type_map[t]["success"] += 1 if e.status == "success" else 0

    type_stats = list(type_map.values())
    for ts in type_stats:
        ts["success"] = round(ts["success"] / ts["count"] * 100) if ts["count"] > 0 else 0

    totals = {
        "total": sum(d["total"] for d in days),
        "success": sum(d["success"] for d in days),
        "failed": sum(d["failed"] for d in days),
    }

    return {"stats": days, "task_types": type_stats, "totals": totals}
