from fastapi import APIRouter, Depends, UploadFile, File, Query, HTTPException
from sqlalchemy.orm import Session
import os
import uuid

from database import get_db
from config import settings
from models.media import Media
from schemas.media import MediaResponse
from dependencies import get_current_user
from models.user import User
from tenant import tenant_scope

router = APIRouter(prefix="/api/biz/v2", tags=["media"])

# 上传安全限制：单文件 ≤ 10MB（防磁盘/内存 DoS）
MAX_UPLOAD_BYTES = 10 * 1024 * 1024
# SVG 可含脚本，禁止作为图片内联渲染（降为 other 并强制下载，防存储型 XSS）
SVG_EXTENSIONS = {".svg", ".svgz"}
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp"}
VIDEO_EXTENSIONS = {".mp4", ".mov", ".avi", ".webm"}


@router.get("/media/")
def list_media(
    file_type: str = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(Media)
    # 租户隔离：非 admin 只能看自己的素材
    scope = tenant_scope(Media, current_user)
    if scope is not None:
        query = query.filter(scope)
    query = query.order_by(Media.created_at.desc())
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
    ext_lower = ext.lower()

    # 大小限制：先读前 N 字节判断是否超限，超限直接拒绝，避免整读大文件占内存
    content = await file.read(MAX_UPLOAD_BYTES + 1)
    if len(content) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail=f"文件过大，上限 {MAX_UPLOAD_BYTES // (1024 * 1024)}MB")

    # SVG 存在脚本注入风险，禁止作为图片内联渲染
    if ext_lower in SVG_EXTENSIONS:
        raise HTTPException(status_code=400, detail="不支持上传 SVG 文件（存在脚本注入风险）")

    unique_name = f"{uuid.uuid4().hex}{ext}"
    file_path = os.path.join(settings.UPLOAD_DIR, unique_name)
    with open(file_path, "wb") as f:
        f.write(content)

    if ext_lower in IMAGE_EXTENSIONS:
        ftype = "image"
    elif ext_lower in VIDEO_EXTENSIONS:
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
    if current_user.role != "admin":
        item.api_id = current_user.api_id or ""
    db.add(item)
    db.commit()
    db.refresh(item)
    return MediaResponse.model_validate(item)
