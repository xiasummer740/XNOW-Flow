from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from database import get_db
from models.task_execution import TaskExecution
from schemas.task_execution import TaskExecutionResponse
from schemas.common import PaginatedResponse
from dependencies import get_current_user
from models.user import User
from tenant import tenant_scope

router = APIRouter(prefix="/api/biz/v2", tags=["task_executions"])


@router.get("/task-executions/", response_model=PaginatedResponse)
def list_task_executions(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(TaskExecution)
    # 租户隔离：非 admin 只能看自己的执行记录
    scope = tenant_scope(TaskExecution, current_user)
    if scope is not None:
        query = query.filter(scope)
    total = query.count()
    execs = (
        query
        .order_by(TaskExecution.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return PaginatedResponse(
        count=total,
        results=[TaskExecutionResponse.model_validate(e) for e in execs],
    )
