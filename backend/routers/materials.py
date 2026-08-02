"""素材管理 — 头像/昵称/签名/链接/文案 分组 + 条目 CRUD
用于"修改资料""自动发视频""自动评论"等功能的素材库
"""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import Optional
import logging

from database import get_db
from models.material import MaterialGroup, Material
from models.user import User
from dependencies import get_current_user
from tenant import tenant_scope, ensure_owned

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/biz/v2", tags=["materials"])

# 合法的素材类别
VALID_CATEGORIES = {"avatar", "nickname", "signature", "link", "title", "comment", "bio", "dm"}


def _ensure_category(category: str):
    if category not in VALID_CATEGORIES:
        raise HTTPException(status_code=400, detail=f"非法类别: {category}，可选 {sorted(VALID_CATEGORIES)}")


# ============ 素材分组 ============

@router.get("/material-groups/")
def list_groups(
    category: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(MaterialGroup)
    scope = tenant_scope(MaterialGroup, current_user)
    if scope is not None:
        query = query.filter(scope)
    if category:
        _ensure_category(category)
        query = query.filter(MaterialGroup.category == category)
    groups = query.order_by(MaterialGroup.id.desc()).all()
    # 附带条目数
    results = []
    for g in groups:
        item_count = db.query(Material).filter(Material.group_id == g.id, Material.status == "active").count()
        g.item_count = item_count
        results.append({
            "id": g.id, "name": g.name, "category": g.category,
            "description": g.description, "item_count": item_count,
            "created_at": g.created_at,
        })
    return {"count": len(results), "results": results}


@router.post("/material-groups/", status_code=201)
def create_group(
    body: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    category = body.get("category", "nickname")
    _ensure_category(category)
    name = (body.get("name") or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="分组名不能为空")
    group = MaterialGroup(
        name=name,
        category=category,
        description=body.get("description", ""),
        api_id=current_user.api_id or "",
    )
    db.add(group)
    db.commit()
    db.refresh(group)
    return {"id": group.id, "name": group.name, "category": group.category}


@router.delete("/material-groups/{group_id}/")
def delete_group(
    group_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    group = db.query(MaterialGroup).filter(MaterialGroup.id == group_id).first()
    if not group:
        raise HTTPException(status_code=404, detail="分组不存在")
    ensure_owned(group, current_user)
    # 删除分组下素材
    db.query(Material).filter(Material.group_id == group_id).delete()
    db.delete(group)
    db.commit()
    return {"message": "删除成功"}


# ============ 素材条目 ============

@router.get("/materials/")
def list_materials(
    group_id: Optional[int] = Query(None),
    category: Optional[str] = Query(None),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(Material)
    scope = tenant_scope(Material, current_user)
    if scope is not None:
        query = query.filter(scope)
    if group_id:
        query = query.filter(Material.group_id == group_id)
    if category:
        _ensure_category(category)
        query = query.filter(Material.category == category)
    items = query.order_by(Material.id.desc()).limit(limit).all()
    return {"count": len(items), "results": [
        {"id": m.id, "group_id": m.group_id, "category": m.category,
         "content": m.content, "image_url": m.image_url, "used_count": m.used_count,
         "created_at": m.created_at} for m in items
    ]}


@router.post("/materials/", status_code=201)
def create_material(
    body: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    category = body.get("category", "nickname")
    _ensure_category(category)
    content = (body.get("content") or "").strip()
    image_url = (body.get("image_url") or "").strip()
    if not content and not image_url:
        raise HTTPException(status_code=400, detail="内容不能为空")
    mat = Material(
        group_id=body.get("group_id") or 0,
        category=category,
        content=content,
        image_url=image_url,
        api_id=current_user.api_id or "",
    )
    db.add(mat)
    # 更新分组计数
    if mat.group_id:
        g = db.query(MaterialGroup).filter(MaterialGroup.id == mat.group_id).first()
        if g:
            g.item_count = db.query(Material).filter(Material.group_id == g.id).count() + 1
    db.commit()
    db.refresh(mat)
    return {"id": mat.id, "category": mat.category, "content": mat.content}


@router.post("/materials/batch/", status_code=201)
def batch_create_materials(
    body: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """批量导入素材（支持多行文本）
    body: {category, group_id, contents: ["a","b",...]}
    """
    category = body.get("category", "nickname")
    _ensure_category(category)
    contents = body.get("contents") or []
    if not isinstance(contents, list) or not contents:
        raise HTTPException(status_code=400, detail="contents 不能为空")
    count = 0
    for c in contents:
        c = (c or "").strip()
        if not c:
            continue
        db.add(Material(group_id=body.get("group_id") or 0, category=category,
                        content=c, api_id=current_user.api_id or ""))
        count += 1
    db.commit()
    return {"message": f"批量导入 {count} 条素材"}


@router.delete("/materials/{material_id}/")
def delete_material(
    material_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    mat = db.query(Material).filter(Material.id == material_id).first()
    if not mat:
        raise HTTPException(status_code=404, detail="素材不存在")
    ensure_owned(mat, current_user)
    db.delete(mat)
    db.commit()
    return {"message": "删除成功"}


# ============ 随机取素材（自动发视频用） ============

@router.get("/materials/random/")
def random_material(
    category: Optional[str] = Query("title"),
    group_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """随机取一条激活素材（用于自动发视频选标题/文案）"""
    _ensure_category(category)
    query = db.query(Material).filter(
        Material.status == "active", Material.category == category
    )
    scope = tenant_scope(Material, current_user)
    if scope is not None:
        query = query.filter(scope)
    if group_id:
        query = query.filter(Material.group_id == group_id)
    mat = query.order_by(func.random()).first()
    if not mat:
        raise HTTPException(status_code=404, detail=f"类别 {category} 暂无可用素材")
    mat.used_count = (mat.used_count or 0) + 1
    db.commit()
    return {"id": mat.id, "category": mat.category, "content": mat.content, "group_id": mat.group_id}


@router.post("/materials/random-batch/")
def random_materials_batch(
    body: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """批量随机取素材（用于自动发视频队列）
    body: {category, count, group_id?}
    """
    category = body.get("category", "title")
    _ensure_category(category)
    try:
        count = int(body.get("count") or 1)
    except (TypeError, ValueError):
        raise HTTPException(status_code=400, detail="count 需为整数")
    if count < 1:
        count = 1
    if count > 100:
        count = 100

    query = db.query(Material).filter(
        Material.status == "active", Material.category == category
    )
    scope = tenant_scope(Material, current_user)
    if scope is not None:
        query = query.filter(scope)
    if body.get("group_id"):
        try:
            query = query.filter(Material.group_id == int(body["group_id"]))
        except (TypeError, ValueError):
            raise HTTPException(status_code=400, detail="group_id 需为整数")

    mats = query.order_by(func.random()).limit(count).all()
    results = []
    for m in mats:
        m.used_count = (m.used_count or 0) + 1
        results.append({"id": m.id, "category": m.category, "content": m.content, "group_id": m.group_id})
    db.commit()
    return {"count": len(results), "results": results}
