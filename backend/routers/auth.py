from fastapi import APIRouter

router = APIRouter(prefix="/api/auth", tags=["auth"])


@router.get("")
def auth_root():
    return {"message": "auth router placeholder"}
