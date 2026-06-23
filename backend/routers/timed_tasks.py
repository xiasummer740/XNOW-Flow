from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database import get_db
from models.timed_task import TimedTask
from schemas.timed_task import TimedTaskResponse, TimedTaskCreateRequest, TimedTaskUpdateRequest
from schemas.common import MessageResponse
from dependencies import get_current_user
from models.user import User

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
    tasks = db.query(TimedTask).order_by(TimedTask.id).all()
    return [_serialize_timed_task(t) for t in tasks]


@router.post("/timed-tasks/", status_code=201)
def create_timed_task(
    req: TimedTaskCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    task = TimedTask(name=req.name, cron=req.cron, task_type=req.task_type)
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
    if req.name is not None:
        task.name = req.name
    if req.cron is not None:
        task.cron = req.cron
    if req.task_type is not None:
        task.task_type = req.task_type
    if req.enabled is not None:
        task.enabled = req.enabled
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
    db.delete(task)
    db.commit()
    return MessageResponse(message="删除成功")
