from fastapi import APIRouter

router = APIRouter(prefix="/api/task-executions", tags=["task_executions"])


@router.get("")
def task_executions_root():
    return {"message": "task_executions router placeholder"}
