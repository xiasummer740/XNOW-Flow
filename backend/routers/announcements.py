from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database import get_db
from models.announcement import Announcement
from schemas.announcement import AnnouncementResponse
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["announcements"])


@router.get("/announcements/")
def list_announcements(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    items = (
        db.query(Announcement)
        .filter(Announcement.is_active == True)
        .order_by(Announcement.is_pinned.desc(), Announcement.created_at.desc())
        .all()
    )
    return [AnnouncementResponse.model_validate(i) for i in items]
