from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from database import get_db
from models.device import DeviceBinding
from schemas.device import DeviceResponse
from schemas.common import PaginatedResponse
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["devices"])


@router.get("/device-bindings/", response_model=PaginatedResponse)
def list_devices(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    total = db.query(DeviceBinding).count()
    devices = db.query(DeviceBinding).offset(offset).limit(limit).all()
    return PaginatedResponse(
        count=total,
        results=[DeviceResponse.model_validate(d) for d in devices],
    )
