from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from database import get_db
from models.collected_data import CollectedData
from schemas.collected_data import CollectedDataResponse
from schemas.common import PaginatedResponse
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["collected_data"])


@router.get("/collected-data/", response_model=PaginatedResponse)
def list_collected_data(
    source: str = Query(None),
    source_type: str = Query(None),
    search: str = Query(None),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(CollectedData)
    if source:
        query = query.filter(CollectedData.source == source)
    if source_type:
        query = query.filter(CollectedData.source_type == source_type)
    if search:
        query = query.filter(CollectedData.content.contains(search))
    total = query.count()
    items = (
        query.order_by(CollectedData.collected_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return PaginatedResponse(
        count=total,
        results=[CollectedDataResponse.model_validate(i) for i in items],
    )
