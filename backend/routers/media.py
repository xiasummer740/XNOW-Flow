from fastapi import APIRouter

router = APIRouter(prefix="/api/media", tags=["media"])


@router.get("")
def media_root():
    return {"message": "media router placeholder"}
