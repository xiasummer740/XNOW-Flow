from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from database import get_db
from models.feedback import Feedback
from schemas.feedback import FeedbackResponse, FeedbackCreateRequest
from schemas.common import PaginatedResponse
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["feedback"])


@router.get("/feedback/", response_model=PaginatedResponse)
def list_feedback(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    total = db.query(Feedback).count()
    items = (
        db.query(Feedback)
        .order_by(Feedback.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return PaginatedResponse(
        count=total,
        results=[FeedbackResponse.model_validate(i) for i in items],
    )


@router.post("/feedback/", response_model=FeedbackResponse, status_code=201)
def create_feedback(
    req: FeedbackCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    item = Feedback(title=req.title, content=req.content, contact=req.contact)
    db.add(item)
    db.commit()
    db.refresh(item)
    return FeedbackResponse.model_validate(item)
