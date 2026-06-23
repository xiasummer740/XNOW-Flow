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


@router.get("/accounts/stats/")
def account_stats(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    accounts = db.query(Account).all()
    return {
        "total": len(accounts),
        "active": sum(1 for a in accounts if a.status == "active"),
        "risk_control": sum(1 for a in accounts if a.status == "risk_control"),
        "offline": sum(1 for a in accounts if a.status not in ("active", "executing", "risk_control")),
        "today_fans_gain": 0,
    }
