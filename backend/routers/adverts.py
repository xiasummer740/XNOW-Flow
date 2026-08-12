"""广告管理端点（PPT 参考产品广告管理模块）
"""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import Optional

from database import get_db
from models.advert import Advert
from dependencies import get_current_user
from models.user import User
from tenant import tenant_scope
from schemas.common import MessageResponse

router = APIRouter(prefix="/api/biz/v2", tags=["adverts"])


@router.get("/adverts/")
def list_adverts(
    status: Optional[str] = Query(None),
    search: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(Advert)
    scope = tenant_scope(Advert, current_user)
    if scope is not None:
        query = query.filter(scope)
    if status:
        query = query.filter(Advert.status == status)
    if search:
        query = query.filter(Advert.title.contains(search))
    total = query.count()
    items = query.order_by(Advert.id.desc()).offset(offset).limit(limit).all()
    return {
        "count": total,
        "results": [
            {
                "id": a.id, "title": a.title, "image_url": a.image_url,
                "link": a.link, "description": a.description,
                "status": a.status, "created_at": a.created_at,
            }
            for a in items
        ],
    }


@router.post("/adverts/", status_code=201)
def create_advert(
    body: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    adv = Advert(
        title=(body.get("title") or "").strip(),
        image_url=body.get("image_url") or "",
        link=body.get("link") or "",
        description=body.get("description") or "",
        status="active",
    )
    if current_user.role != "admin":
        adv.api_id = current_user.api_id or ""
    db.add(adv)
    db.commit()
    db.refresh(adv)
    return {"id": adv.id, "title": adv.title, "status": adv.status}


@router.put("/adverts/{advert_id}/")
def update_advert(
    advert_id: int,
    body: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    adv = db.query(Advert).filter(Advert.id == advert_id).first()
    if not adv:
        raise HTTPException(status_code=404, detail="广告不存在")
    if current_user.role != "admin" and adv.api_id != (current_user.api_id or ""):
        raise HTTPException(status_code=403, detail="无权操作")
    if "title" in body:
        adv.title = body["title"]
    if "image_url" in body:
        adv.image_url = body["image_url"]
    if "link" in body:
        adv.link = body["link"]
    if "description" in body:
        adv.description = body["description"]
    if "status" in body:
        adv.status = body["status"]
    db.commit()
    return {"id": adv.id, "title": adv.title, "status": adv.status}


@router.delete("/adverts/{advert_id}/", response_model=MessageResponse)
def delete_advert(
    advert_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    adv = db.query(Advert).filter(Advert.id == advert_id).first()
    if not adv:
        raise HTTPException(status_code=404, detail="广告不存在")
    if current_user.role != "admin" and adv.api_id != (current_user.api_id or ""):
        raise HTTPException(status_code=403, detail="无权操作")
    db.delete(adv)
    db.commit()
    return MessageResponse(message="已删除")
