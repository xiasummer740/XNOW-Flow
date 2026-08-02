"""定时发视频任务 — 创建/查询/删除/下发
用于"自动发视频"功能：创建视频发布任务，向设备下发 post_video 指令
"""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import Optional
from datetime import datetime, timezone
import logging

from database import get_db
from models.video_post import VideoPost
from models.user import User
from dependencies import get_current_user
from tenant import tenant_scope, ensure_owned
from connection_manager import manager

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/biz/v2", tags=["video_posts"])

VALID_STATUSES = {"pending", "processing", "done", "failed"}


def _parse_iso_datetime(value):
    """容错解析 ISO8601：接受 naive/aware 与 'Z' 后缀，统一返回 aware UTC。
    解析失败抛 ValueError，由调用方转 400。"""
    s = str(value).strip().replace("Z", "+00:00")
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


@router.post("/video-posts/", status_code=201)
def create_video_post(
    body: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """创建视频发布任务
    body: {device_id, video_url, title, scheduled_at?, category?}
    """
    device_id = (body.get("device_id") or "").strip()
    video_url = (body.get("video_url") or "").strip()
    title = (body.get("title") or "").strip()
    if not device_id:
        raise HTTPException(status_code=400, detail="device_id 不能为空")
    if not video_url and not title:
        raise HTTPException(status_code=400, detail="video_url 和 title 至少填一个")

    category = body.get("category") or "auto_post"
    scheduled_at = None
    if body.get("scheduled_at"):
        try:
            scheduled_at = _parse_iso_datetime(body["scheduled_at"])
        except Exception:
            raise HTTPException(status_code=400, detail="scheduled_at 格式非法，需 ISO8601")

    post = VideoPost(
        device_id=device_id,
        video_url=video_url,
        title=title,
        category=category,
        status="pending",
        scheduled_at=scheduled_at,
        api_id=current_user.api_id or "",
    )
    db.add(post)
    db.commit()
    db.refresh(post)
    return {
        "id": post.id,
        "device_id": post.device_id,
        "video_url": post.video_url,
        "title": post.title,
        "category": post.category,
        "status": post.status,
        "scheduled_at": post.scheduled_at,
        "created_at": post.created_at,
    }


@router.get("/video-posts/")
def list_video_posts(
    status: Optional[str] = Query(None),
    device_id: Optional[str] = Query(None),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """查询视频发布任务，可按状态/设备过滤"""
    query = db.query(VideoPost)
    scope = tenant_scope(VideoPost, current_user)
    if scope is not None:
        query = query.filter(scope)
    if status:
        if status not in VALID_STATUSES:
            raise HTTPException(status_code=400, detail=f"非法状态: {status}，可选 {sorted(VALID_STATUSES)}")
        query = query.filter(VideoPost.status == status)
    if device_id:
        query = query.filter(VideoPost.device_id == device_id)
    posts = query.order_by(VideoPost.id.desc()).limit(limit).all()
    return {"count": len(posts), "results": [
        {
            "id": p.id,
            "device_id": p.device_id,
            "video_url": p.video_url,
            "title": p.title,
            "category": p.category,
            "status": p.status,
            "scheduled_at": p.scheduled_at,
            "result": p.result,
            "created_at": p.created_at,
        } for p in posts
    ]}


@router.delete("/video-posts/{post_id}/")
def delete_video_post(
    post_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """删除视频发布任务"""
    post = db.query(VideoPost).filter(VideoPost.id == post_id).first()
    if not post:
        raise HTTPException(status_code=404, detail="任务不存在")
    ensure_owned(post, current_user)
    db.delete(post)
    db.commit()
    return {"message": "删除成功"}


@router.post("/video-posts/{post_id}/dispatch/")
async def dispatch_video_post(
    post_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """下发发视频指令到设备（WebSocket 直发 → HTTP 轮询队列）"""
    post = db.query(VideoPost).filter(VideoPost.id == post_id).first()
    if not post:
        raise HTTPException(status_code=404, detail="任务不存在")
    ensure_owned(post, current_user)
    if not post.device_id:
        raise HTTPException(status_code=400, detail="任务缺少 device_id")
    from tenant import resolve_owned_device
    if not resolve_owned_device(db, post.device_id, current_user):
        raise HTTPException(status_code=404, detail="设备不存在")

    command = {
        "type": "command",
        "action": "post_video",
        "params": {
            "title": post.title or "",
            "video_url": post.video_url or "",
            "post_id": post.id,
        },
        "timestamp": datetime.utcnow().isoformat(),
    }
    success, via_ws = await manager.send_or_enqueue_command(post.device_id, command)

    # 更新状态为处理中
    post.status = "processing"
    db.commit()

    via = "WebSocket" if via_ws else "HTTP轮询队列"
    return {
        "success": True,
        "message": f"发视频指令已下发({via})",
        "via": via,
        "post_id": post.id,
    }
