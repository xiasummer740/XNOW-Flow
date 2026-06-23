from fastapi import APIRouter

router = APIRouter(prefix="/api/devices", tags=["devices"])


@router.get("")
def devices_root():
    return {"message": "devices router placeholder"}
