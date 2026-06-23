from fastapi import APIRouter

router = APIRouter(prefix="/api/timed-tasks", tags=["timed_tasks"])


@router.get("")
def timed_tasks_root():
    return {"message": "timed_tasks router placeholder"}
