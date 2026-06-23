from fastapi import APIRouter

router = APIRouter(prefix="/api/announcements", tags=["announcements"])


@router.get("")
def announcements_root():
    return {"message": "announcements router placeholder"}
