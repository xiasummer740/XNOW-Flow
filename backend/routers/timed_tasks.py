from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database import get_db
from models.timed_task import TimedTask
from schemas.timed_task import TimedTaskResponse, TimedTaskCreateRequest, TimedTaskUpdateRequest
from schemas.common import MessageResponse
from dependencies import get_current_user
from models.user import User
from tenant import tenant_scope, ensure_owned

router = APIRouter(prefix="/api/biz/v2", tags=["timed_tasks"])


def _serialize_timed_task(t: TimedTask):
    return TimedTaskResponse(
        id=t.id,
        name=t.name,
        cron=t.cron,
        task_type=t.task_type,
        enabled=t.enabled,
        last_run=t.last_run.strftime("%Y-%m-%d %H:%M") if t.last_run else "—",
        next_run=t.next_run.strftime("%Y-%m-%d %H:%M") if t.next_run else "—",
    )


@router.get("/timed-tasks/")
def list_timed_tasks(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(TimedTask)
    # 租户隔离：非 admin 只能看自己的定时任务
    scope = tenant_scope(TimedTask, current_user)
    if scope is not None:
        query = query.filter(scope)
    tasks = query.order_by(TimedTask.id).all()
    return [_serialize_timed_task(t) for t in tasks]


@router.post("/timed-tasks/", status_code=201)
def create_timed_task(
    req: TimedTaskCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    import json as _json
    task = TimedTask(name=req.name, cron=req.cron, task_type=req.task_type)
    task.device_ids = _json.dumps(req.device_ids or [])
    task.action = req.action or ""
    task.params = _json.dumps(req.params or {})
    if current_user.role != "admin":
        task.api_id = current_user.api_id or ""
    db.add(task)
    db.commit()
    db.refresh(task)
    return _serialize_timed_task(task)


@router.put("/timed-tasks/{task_id}/")
def update_timed_task(
    task_id: int,
    req: TimedTaskUpdateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    task = db.query(TimedTask).filter(TimedTask.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="定时任务不存在")
    ensure_owned(task, current_user)
    if req.name is not None:
        task.name = req.name
    if req.cron is not None:
        task.cron = req.cron
    if req.task_type is not None:
        task.task_type = req.task_type
    if req.enabled is not None:
        task.enabled = req.enabled
    import json as _json
    if req.device_ids is not None:
        task.device_ids = _json.dumps(req.device_ids)
    if req.action is not None:
        task.action = req.action
    if req.params is not None:
        task.params = _json.dumps(req.params)
    db.commit()
    db.refresh(task)
    return _serialize_timed_task(task)


@router.delete("/timed-tasks/{task_id}/")
def delete_timed_task(
    task_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    task = db.query(TimedTask).filter(TimedTask.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="定时任务不存在")
    ensure_owned(task, current_user)
    db.delete(task)
    db.commit()
    return MessageResponse(message="删除成功")
