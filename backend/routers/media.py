from fastapi import APIRouter, Depends, UploadFile, File, Query
from sqlalchemy.orm import Session
import os
import uuid

from database import get_db
from config import settings
from models.media import Media
from schemas.media import MediaResponse
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["media"])


@router.get("/media/")
def list_media(
    file_type: str = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(Media).order_by(Media.created_at.desc())
    if file_type:
        query = query.filter(Media.file_type == file_type)
    items = query.all()
    return [MediaResponse.model_validate(i) for i in items]


@router.post("/media/upload/", status_code=201)
async def upload_media(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    os.makedirs(settings.UPLOAD_DIR, exist_ok=True)
    ext = os.path.splitext(file.filename or "file")[1]
    unique_name = f"{uuid.uuid4().hex}{ext}"
    file_path = os.path.join(settings.UPLOAD_DIR, unique_name)
    content = await file.read()
    with open(file_path, "wb") as f:
        f.write(content)

    ext_lower = ext.lower()
    if ext_lower in (".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg"):
        ftype = "image"
    elif ext_lower in (".mp4", ".mov", ".avi", ".webm"):
        ftype = "video"
    else:
        ftype = "other"

    item = Media(
        filename=unique_name,
        original_name=file.filename,
        file_type=ftype,
        file_size=len(content),
        url=f"/uploads/{unique_name}",
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return MediaResponse.model_validate(item)
