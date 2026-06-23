from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from database import get_db
from models.account import Account
from schemas.account import AccountResponse
from schemas.common import PaginatedResponse
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["accounts"])


@router.get("/accounts/", response_model=PaginatedResponse)
def list_accounts(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    total = db.query(Account).count()
    accounts = db.query(Account).offset(offset).limit(limit).all()
    return PaginatedResponse(
        count=total,
        results=[AccountResponse.model_validate(a) for a in accounts],
    )
