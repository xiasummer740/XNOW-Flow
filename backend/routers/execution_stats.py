from fastapi import APIRouter

router = APIRouter(prefix="/api/execution-stats", tags=["execution_stats"])


@router.get("")
def execution_stats_root():
    return {"message": "execution_stats router placeholder"}
