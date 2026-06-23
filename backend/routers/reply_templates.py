from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database import get_db
from models.reply_template import ReplyTemplate
from schemas.reply_template import (
    ReplyTemplateResponse,
    ReplyTemplateCreateRequest,
    ReplyTemplateUpdateRequest,
)
from schemas.common import MessageResponse
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["reply_templates"])


@router.get("/reply-templates/")
def list_templates(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    items = (
        db.query(ReplyTemplate)
        .order_by(ReplyTemplate.created_at.desc())
        .all()
    )
    return [ReplyTemplateResponse.model_validate(i) for i in items]


@router.post("/reply-templates/", status_code=201)
def create_template(
    req: ReplyTemplateCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    item = ReplyTemplate(
        name=req.name,
        content=req.content,
        match_type=req.match_type,
        match_rule=req.match_rule,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return ReplyTemplateResponse.model_validate(item)


@router.put("/reply-templates/{template_id}/")
def update_template(
    template_id: int,
    req: ReplyTemplateUpdateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    item = (
        db.query(ReplyTemplate)
        .filter(ReplyTemplate.id == template_id)
        .first()
    )
    if not item:
        raise HTTPException(status_code=404, detail="模板不存在")
    if req.name is not None:
        item.name = req.name
    if req.content is not None:
        item.content = req.content
    if req.match_type is not None:
        item.match_type = req.match_type
    if req.match_rule is not None:
        item.match_rule = req.match_rule
    if req.is_active is not None:
        item.is_active = req.is_active
    db.commit()
    db.refresh(item)
    return ReplyTemplateResponse.model_validate(item)


@router.delete("/reply-templates/{template_id}/")
def delete_template(
    template_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    item = (
        db.query(ReplyTemplate)
        .filter(ReplyTemplate.id == template_id)
        .first()
    )
    if not item:
        raise HTTPException(status_code=404, detail="模板不存在")
    db.delete(item)
    db.commit()
    return MessageResponse(message="删除成功")
