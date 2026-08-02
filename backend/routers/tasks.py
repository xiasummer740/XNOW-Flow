from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from database import get_db
from models.task import Task
from schemas.task import TaskResponse, TaskCreateRequest
from schemas.common import PaginatedResponse
from dependencies import get_current_user
from models.user import User
from tenant import tenant_scope

router = APIRouter(prefix="/api/biz/v2", tags=["tasks"])


@router.get("/tasks/", response_model=PaginatedResponse)
def list_tasks(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(Task)
    # 租户隔离：非 admin 只能看自己的任务
    scope = tenant_scope(Task, current_user)
    if scope is not None:
        query = query.filter(scope)
    total = query.count()
    tasks = (
        query
        .order_by(Task.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return PaginatedResponse(
        count=total,
        results=[TaskResponse.model_validate(t) for t in tasks],
    )


@router.post("/tasks/", response_model=TaskResponse, status_code=201)
def create_task(
    req: TaskCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    task = Task(
        type=req.type,
        target=req.target,
        device=req.device,
        account=req.account,
        name=f"{req.type}任务-{req.target[:20]}" if req.target else f"{req.type}任务",
        status="pending",
        progress=0,
    )
    if current_user.role != "admin":
        task.api_id = current_user.api_id or ""
    db.add(task)
    db.commit()
    db.refresh(task)
    return TaskResponse.model_validate(task)
