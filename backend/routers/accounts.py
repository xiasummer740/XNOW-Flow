from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import or_
from typing import Optional

from database import get_db
from models.account import Account
from schemas.account import AccountResponse
from schemas.common import PaginatedResponse, MessageResponse
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["accounts"])


@router.get("/accounts/", response_model=PaginatedResponse)
def list_accounts(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    search: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(Account)

    if search:
        query = query.filter(
            or_(
                Account.nickname.contains(search),
                Account.aweme_number.contains(search),
                Account.phone.contains(search),
                Account.username.contains(search),
            )
        )

    if status and status != "all":
        query = query.filter(Account.status == status)

    total = query.count()
    accounts = query.order_by(Account.id.desc()).offset(offset).limit(limit).all()
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


@router.get("/accounts/{account_id}/")
def get_account(
    account_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    account = db.query(Account).filter(Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="账号不存在")
    return AccountResponse.model_validate(account)


@router.patch("/accounts/{account_id}/")
def update_account(
    account_id: int,
    updates: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    account = db.query(Account).filter(Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="账号不存在")
    for key, value in updates.items():
        if hasattr(account, key):
            setattr(account, key, value)
    db.commit()
    db.refresh(account)
    return AccountResponse.model_validate(account)
