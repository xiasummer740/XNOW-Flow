from fastapi import APIRouter

router = APIRouter(prefix="/api/tasks", tags=["tasks"])


@router.get("")
def tasks_root():
    return {"message": "tasks router placeholder"}
