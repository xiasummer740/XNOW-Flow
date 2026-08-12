from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func

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
from tenant import tenant_scope, ensure_owned

router = APIRouter(prefix="/api/biz/v2", tags=["reply_templates"])


@router.get("/reply-templates/")
def list_templates(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(ReplyTemplate)
    # 租户隔离：非 admin 只能看自己的话术模板
    scope = tenant_scope(ReplyTemplate, current_user)
    if scope is not None:
        query = query.filter(scope)
    items = (
        query
        .order_by(ReplyTemplate.created_at.desc())
        .all()
    )
    return [ReplyTemplateResponse.model_validate(i) for i in items]


@router.post("/reply-templates/device-random/")
def device_random_template(
    device_id: str = "",
    secret: str = "",
    db: Session = Depends(get_db),
):
    """设备端回关自动私信：随机取一条激活话术（设备 secret 鉴权，不需 admin JWT）"""
    from routers.ws import _verify_device_auth
    if not device_id or not _verify_device_auth(device_id, secret):
        raise HTTPException(status_code=401, detail="unauthorized")
    # 设备归属租户的话术
    from routers.ws import _get_device_api_id
    api_id = _get_device_api_id(device_id) or "1"
    item = (
        db.query(ReplyTemplate)
        .filter(ReplyTemplate.is_active == True,  # noqa: E712
                ReplyTemplate.api_id == api_id)
        .order_by(func.random())
        .first()
    )
    if not item:
        # 回退到全局话术（api_id 空 = 管理员全局模板）
        item = (
            db.query(ReplyTemplate)
            .filter(ReplyTemplate.is_active == True,  # noqa: E712
                    ReplyTemplate.api_id.in_(["", "1"]))
            .order_by(func.random())
            .first()
        )
    if not item:
        raise HTTPException(status_code=404, detail="暂无可用话术模板")
    return ReplyTemplateResponse.model_validate(item)


@router.get("/reply-templates/random/")
def random_template(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """随机取一条激活话术模板（用于自动私信话术）"""
    query = db.query(ReplyTemplate)
    # 租户隔离：非 admin 只能随机取自己租户的话术模板
    scope = tenant_scope(ReplyTemplate, current_user)
    if scope is not None:
        query = query.filter(scope)
    item = (
        query
        .filter(ReplyTemplate.is_active == True)  # noqa: E712
        .order_by(func.random())
        .first()
    )
    if not item:
        raise HTTPException(status_code=404, detail="暂无可用话术模板")
    return ReplyTemplateResponse.model_validate(item)


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
    if current_user.role != "admin":
        item.api_id = current_user.api_id or ""
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
    ensure_owned(item, current_user)
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
    ensure_owned(item, current_user)
    db.delete(item)
    db.commit()
    return MessageResponse(message="删除成功")
