from fastapi import APIRouter

router = APIRouter(prefix="/api/feedback", tags=["feedback"])


@router.get("")
def feedback_root():
    return {"message": "feedback router placeholder"}
