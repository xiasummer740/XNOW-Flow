import json
import base64
import urllib.request
import logging

from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session

from database import get_db
from config import settings
from models.public_user import PublicUser
from models.collected_data import CollectedData
from schemas.public_user import (
    PublicUserResponse,
    PublicFeedRequest,
    PublicCopyRequest,
    PublicTagRequest,
)
from schemas.common import PaginatedResponse, MessageResponse
from dependencies import get_current_user
from models.user import User
from tenant import tenant_scope

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/biz/v2", tags=["public_users"])

# TikTok 头像 CDN 域（抓取时带 UA，防 403）
_AVATAR_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
_TAG_PROMPT = (
    "你是一名用户画像分析师。请分析这张 TikTok 用户头像图片，返回严格 JSON（不要任何其他文字），"
    "格式为 {\"beauty\":\"颜值分0-100\",\"emotion\":\"情绪词(如开心/中性/严肃/可爱)\","
    "\"age\":\"年龄段(如18-24)\",\"glasses\":\"眼镜(是/否)\",\"gender\":\"性别(男/女/未知)\",\"style\":\"风格词(如自拍/风景/动漫/宠物)\"}。"
    "无法判断的字段用\"未知\"。"
)


def _fetch_bytes(url: str, timeout: int = 15) -> bytes:
    """下载图片字节（带 UA + 超时，失败抛异常）"""
    req = urllib.request.Request(url, headers={"User-Agent": _AVATAR_UA})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def _tag_one_avatar(avatar_url: str) -> str:
    """调用 qwen-vl 分析头像，返回标签字符串（逗号分隔）。失败返回空。"""
    if not settings.DASHSCOPE_API_KEY:
        logger.warning("[public-users] DASHSCOPE_API_KEY 未配置，跳过打标")
        return ""
    try:
        img_bytes = _fetch_bytes(avatar_url)
        b64 = base64.b64encode(img_bytes).decode()
        mime = "image/jpeg"
        if avatar_url.lower().endswith(".png"):
            mime = "image/png"
        payload = {
            "model": settings.DASHSCOPE_MODEL,
            "messages": [{
                "role": "user",
                "content": [
                    {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{b64}"}},
                    {"type": "text", "text": _TAG_PROMPT},
                ],
            }],
            "max_tokens": 300,
        }
        req = urllib.request.Request(
            f"{settings.DASHSCOPE_BASE_URL}/chat/completions",
            data=json.dumps(payload).encode(),
            headers={
                "Authorization": f"Bearer {settings.DASHSCOPE_API_KEY}",
                "Content-Type": "application/json",
            },
        )
        with urllib.request.urlopen(req, timeout=40) as resp:
            data = json.loads(resp.read().decode())
        content = data["choices"][0]["message"]["content"]
        # 去可能的 ```json 围栏
        content = content.strip()
        if content.startswith("```"):
            content = content.split("```")[1]
            if content.startswith("json"):
                content = content[4:]
            content = content.strip()
        tags = json.loads(content)
        parts = []
        if tags.get("beauty"):
            parts.append(f"颜值:{tags['beauty']}")
        if tags.get("emotion"):
            parts.append(f"情绪:{tags['emotion']}")
        if tags.get("age"):
            parts.append(f"年龄:{tags['age']}")
        if tags.get("glasses"):
            parts.append(f"眼镜:{tags['glasses']}")
        if tags.get("gender"):
            parts.append(f"性别:{tags['gender']}")
        if tags.get("style"):
            parts.append(f"风格:{tags['style']}")
        return ",".join(parts)
    except Exception as e:
        logger.warning(f"[public-users] 打标失败 {avatar_url[:60]}...: {e}")
        return ""


@router.get("/public-users/", response_model=PaginatedResponse)
def list_public_users(
    gender: str = Query(None),
    country: str = Query(None),
    search: str = Query(None),
    min_followers: int = Query(None, ge=0),
    max_followers: int = Query(None, ge=0),
    keyword: str = Query(None),
    ai_tagged: int = Query(None),       # 1=已打标 0=未打标
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """公共用户库：跨租户筛选（所有用户共享此池）"""
    query = db.query(PublicUser)
    if gender:
        query = query.filter(PublicUser.gender == gender)
    if country:
        query = query.filter(PublicUser.country == country)
    if min_followers is not None:
        query = query.filter(PublicUser.followers >= min_followers)
    if max_followers is not None:
        query = query.filter(PublicUser.followers <= max_followers)
    if keyword:
        query = query.filter(PublicUser.keyword.contains(keyword))
    if ai_tagged is not None:
        query = query.filter(PublicUser.ai_tagged == (1 if ai_tagged else 0))
    if search:
        query = query.filter(PublicUser.nickname.contains(search))
    total = query.count()
    items = (
        query.order_by(PublicUser.followers.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return PaginatedResponse(
        count=total,
        results=[PublicUserResponse.model_validate(i) for i in items],
    )


@router.get("/public-users/stats/")
def public_users_stats(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """公共库统计"""
    from sqlalchemy import func
    by_gender = {
        r[0] or "unknown": r[1]
        for r in db.query(PublicUser.gender, func.count())
        .group_by(PublicUser.gender).all()
    }
    by_country = {
        r[0] or "未知": r[1]
        for r in db.query(PublicUser.country, func.count())
        .group_by(PublicUser.country).all()
    }
    return {
        "total": db.query(PublicUser).count(),
        "tagged": db.query(PublicUser).filter(PublicUser.ai_tagged == 1).count(),
        "by_gender": by_gender,
        "by_country": by_country,
    }


@router.post("/public-users/feed/", response_model=MessageResponse)
def feed_public_users(
    req: PublicFeedRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """把当前租户采集数据投喂到公共库（去标识化 + 全局按 aweme_id 去重）"""
    query = db.query(CollectedData)
    scope = tenant_scope(CollectedData, current_user)
    if scope is not None:
        query = query.filter(scope)
    if req.source_types:
        query = query.filter(CollectedData.source_type.in_(req.source_types))
    if req.group_names:
        query = query.filter(CollectedData.group_name.in_(req.group_names))
    if req.min_followers is not None:
        query = query.filter(CollectedData.followers >= req.min_followers)
    if req.require_avatar:
        query = query.filter(CollectedData.url != "")
    items = query.limit(req.max_count or 500).all()

    inserted = skipped = no_id = 0
    for item in items:
        if not item.aweme_id:
            no_id += 1
            continue
        exists = db.query(PublicUser).filter(PublicUser.aweme_id == item.aweme_id).first()
        if exists:
            skipped += 1
            continue
        db.add(PublicUser(
            aweme_id=item.aweme_id,
            nickname=item.author or "",
            avatar_url=item.url or "",
            gender=item.gender or "",
            country=item.region or "",
            followers=item.followers or 0,
            following_count=item.following_count or 0,
            age=item.age or 0,
            signature=(item.content or "")[:500],
            contributed_by=current_user.api_id or "",
        ))
        inserted += 1
    db.commit()
    return MessageResponse(
        message=f"投喂 {inserted} 条到公共库，跳过重复 {skipped} 条，缺ID跳过 {no_id} 条"
    )


@router.post("/public-users/copy/", response_model=MessageResponse)
def copy_public_users(
    req: PublicCopyRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """把公共库记录复制到当前租户采集数据（source_type=public，按 aweme_id 去重）"""
    if not req.ids:
        raise HTTPException(status_code=400, detail="ids 不能为空")
    users = db.query(PublicUser).filter(PublicUser.id.in_(req.ids)).all()
    if not users:
        raise HTTPException(status_code=404, detail="公共用户不存在")
    api_id = current_user.api_id or ""
    inserted = skipped = 0
    seen = set()
    for u in users:
        dedupe_key = u.aweme_id or f"public:{u.id}"
        if dedupe_key in seen:
            skipped += 1
            continue
        exists = db.query(CollectedData).filter(
            CollectedData.dedupe_key == dedupe_key,
            CollectedData.api_id == api_id,
        ).first()
        if exists:
            skipped += 1
            continue
        seen.add(dedupe_key)
        db.add(CollectedData(
            source="public",
            source_type="public",
            content=u.signature or "",
            author=u.nickname or "",
            url=u.avatar_url or "",
            gender=u.gender or "",
            region=u.country or "",
            followers=u.followers or 0,
            following_count=u.following_count or 0,
            age=u.age or 0,
            aweme_id=u.aweme_id or "",
            group_name=req.group_name or "未分组",
            api_id=api_id,
            dedupe_key=dedupe_key,
        ))
        inserted += 1
    db.commit()
    return MessageResponse(message=f"复制 {inserted} 条到分组[{req.group_name}]，跳过重复 {skipped} 条")


@router.post("/public-users/tag/", response_model=MessageResponse)
def tag_public_users(
    req: PublicTagRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """AI 头像打标：处理未打标且有头像的记录（qwen-vl）"""
    if not settings.DASHSCOPE_API_KEY:
        raise HTTPException(status_code=400, detail="未配置 DASHSCOPE_API_KEY，请在 VPS 环境变量设置后重试")
    limit = max(1, min(req.limit or 10, 50))
    targets = (
        db.query(PublicUser)
        .filter(PublicUser.ai_tagged == 0, PublicUser.avatar_url != "")
        .order_by(PublicUser.id.asc())
        .limit(limit)
        .all()
    )
    if not targets:
        return MessageResponse(message="暂无待打标记录（全部已打标或缺少头像）")
    done = failed = 0
    for u in targets:
        tag = _tag_one_avatar(u.avatar_url)
        if tag:
            u.keyword = tag
            u.ai_tagged = 1
            done += 1
        else:
            # 失败不标记，留待下次重试（不烧记录）
            failed += 1
    db.commit()
    return MessageResponse(message=f"本次打标 {done} 条成功，{failed} 条失败(未标记，可重试)")
