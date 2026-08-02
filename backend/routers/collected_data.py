from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func

from database import get_db
from models.collected_data import CollectedData
from schemas.collected_data import (
    CollectedDataResponse,
    CollectedDataBatchInsert,
    GroupAssignRequest,
    BatchGroupAssignRequest,
)
from schemas.common import PaginatedResponse, MessageResponse
from dependencies import get_current_user
from models.user import User
from tenant import tenant_scope, ensure_owned

router = APIRouter(prefix="/api/biz/v2", tags=["collected_data"])


def _build_dedupe_key(item: dict) -> str:
    """构造去重键：优先 aweme_id，否则用 source_type:author"""
    if item.get("aweme_id"):
        return item["aweme_id"]
    author = item.get("author") or ""
    source_type = item.get("source_type") or "fans"
    return f"{source_type}:{author}"


@router.get("/collected-data/", response_model=PaginatedResponse)
def list_collected_data(
    source: str = Query(None),
    source_type: str = Query(None),
    search: str = Query(None),
    gender: str = Query(None),
    region: str = Query(None),
    group_name: str = Query(None),
    min_followers: int = Query(None, ge=0),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(CollectedData)
    scope = tenant_scope(CollectedData, current_user)
    if scope is not None:
        query = query.filter(scope)
    if source:
        query = query.filter(CollectedData.source == source)
    if source_type:
        query = query.filter(CollectedData.source_type == source_type)
    if gender:
        query = query.filter(CollectedData.gender == gender)
    if region:
        query = query.filter(CollectedData.region == region)
    if group_name:
        query = query.filter(CollectedData.group_name == group_name)
    if min_followers is not None:
        query = query.filter(CollectedData.followers >= min_followers)
    if search:
        query = query.filter(
            CollectedData.author.contains(search) | CollectedData.content.contains(search)
        )
    total = query.count()
    items = (
        query.order_by(CollectedData.collected_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return PaginatedResponse(
        count=total,
        results=[CollectedDataResponse.model_validate(i) for i in items],
    )


@router.post("/collected-data/batch/", response_model=MessageResponse)
def batch_insert_collected_data(
    req: CollectedDataBatchInsert,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """批量插入采集数据（带去重：同一租户下 dedupe_key 已存在则跳过）"""
    if not req.items:
        raise HTTPException(status_code=400, detail="items 不能为空")
    api_id = current_user.api_id or ""
    inserted = 0
    skipped = 0
    for item in req.items:
        if not item.author and not item.aweme_id:
            continue
        dedupe_key = item.dedupe_key or _build_dedupe_key(item.model_dump())
        exists = db.query(CollectedData).filter(
            CollectedData.dedupe_key == dedupe_key,
            CollectedData.api_id == api_id,
        ).first()
        if exists:
            skipped += 1
            continue
        db.add(CollectedData(
            source=item.source or "device",
            source_type=item.source_type or "fans",
            content=item.content or "",
            author=item.author or "",
            url=item.url or "",
            gender=item.gender or "",
            region=item.region or "",
            followers=item.followers or 0,
            aweme_id=item.aweme_id or "",
            group_name=item.group_name or "未分组",
            api_id=api_id,
            remark=item.remark or "",
            dedupe_key=dedupe_key,
        ))
        inserted += 1
    db.commit()
    return MessageResponse(message=f"插入 {inserted} 条，跳过重复 {skipped} 条")


@router.get("/collected-data/stats/")
def collected_data_stats(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """采集数据统计：按性别/地区/分组计数"""
    query = db.query(CollectedData)
    scope = tenant_scope(CollectedData, current_user)
    if scope is not None:
        query = query.filter(scope)

    by_gender = {
        r[0] or "unknown": r[1]
        for r in query.with_entities(CollectedData.gender, func.count())
        .group_by(CollectedData.gender).all()
    }
    by_region = {
        r[0] or "未知": r[1]
        for r in query.with_entities(CollectedData.region, func.count())
        .group_by(CollectedData.region).all()
    }
    by_group = {
        r[0] or "未分组": r[1]
        for r in query.with_entities(CollectedData.group_name, func.count())
        .group_by(CollectedData.group_name).all()
    }
    by_source_type = {
        r[0] or "unknown": r[1]
        for r in query.with_entities(CollectedData.source_type, func.count())
        .group_by(CollectedData.source_type).all()
    }
    return {
        "total": query.count(),
        "by_gender": by_gender,
        "by_region": by_region,
        "by_group": by_group,
        "by_source_type": by_source_type,
    }


@router.api_route("/collected-data/groups/", methods=["GET", "POST"])
def list_collected_data_groups(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """列出所有分组名 + 计数（分组 UI 用）"""
    query = db.query(CollectedData.group_name, func.count().label("count"))
    scope = tenant_scope(CollectedData, current_user)
    if scope is not None:
        query = query.filter(scope)
    rows = query.group_by(CollectedData.group_name).order_by(func.count().desc()).all()
    return {"groups": [{"name": r[0] or "未分组", "count": r[1]} for r in rows]}


@router.post("/collected-data/{item_id}/group/", response_model=MessageResponse)
def set_collected_data_group(
    item_id: int,
    req: GroupAssignRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """设置单条采集数据的分组"""
    item = db.query(CollectedData).filter(CollectedData.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="数据不存在")
    ensure_owned(item, current_user)
    item.group_name = req.group_name or "未分组"
    db.commit()
    return MessageResponse(message="分组已更新")


@router.post("/collected-data/group/set-batch/", response_model=MessageResponse)
def batch_set_collected_data_group(
    req: BatchGroupAssignRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """批量设置采集数据分组"""
    if not req.ids:
        raise HTTPException(status_code=400, detail="ids 不能为空")
    items = db.query(CollectedData).filter(CollectedData.id.in_(req.ids)).all()
    if not items:
        raise HTTPException(status_code=404, detail="数据不存在")
    for item in items:
        ensure_owned(item, current_user)
        item.group_name = req.group_name or "未分组"
    db.commit()
    return MessageResponse(message=f"已更新 {len(items)} 条数据分组")


@router.delete("/collected-data/{item_id}/", response_model=MessageResponse)
def delete_collected_data(
    item_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """删除单条采集数据"""
    item = db.query(CollectedData).filter(CollectedData.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="数据不存在")
    ensure_owned(item, current_user)
    db.delete(item)
    db.commit()
    return MessageResponse(message="已删除")
