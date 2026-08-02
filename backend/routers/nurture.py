"""养号计划（批量自动养号引擎）— 创建/查询/删除/开始/暂停

- 创建养号计划（tenant 隔离）
- start: 激活计划并立即向每台设备下发 nurture_tick
- pause: 暂停计划并向每台设备下发 nurture_stop
- 后台 scheduler（backend/main.py 中启动）每 30 分钟为所有 active 计划下发 nurture_tick
"""
import json
import logging
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import Optional

from database import get_db, SessionLocal
from models.nurture_plan import NurturePlan
from models.user import User
from dependencies import get_current_user
from tenant import tenant_scope, ensure_owned
from connection_manager import manager

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/biz/v2", tags=["nurture"])

VALID_STATUSES = {"active", "paused", "completed"}


# ========== 序列化 / 解析辅助 ==========

def _parse_json(text, fallback):
    if not text:
        return fallback
    try:
        return json.loads(text)
    except (json.JSONDecodeError, TypeError):
        return fallback


def _parse_device_ids(plan: NurturePlan) -> list:
    ids = _parse_json(plan.device_ids, [])
    return [d for d in (ids or []) if isinstance(d, str) and d.strip()]


def _parse_daily_actions(plan: NurturePlan) -> dict:
    return _parse_json(plan.daily_actions, {})


def _serialize_plan(p: NurturePlan) -> dict:
    return {
        "id": p.id,
        "name": p.name,
        "device_ids": _parse_json(p.device_ids, []),
        "account_ids": _parse_json(p.account_ids, []),
        "daily_actions": _parse_json(p.daily_actions, {}),
        "status": p.status,
        "start_date": p.start_date.isoformat() if p.start_date else None,
        "end_date": p.end_date.isoformat() if p.end_date else None,
        "api_id": p.api_id,
        "created_at": p.created_at.isoformat() if p.created_at else None,
    }


# ========== 指令构造 / 下发 ==========

def _build_nurture_command(plan: NurturePlan, action: str) -> dict:
    """构造 nurture_tick / nurture_stop 指令载荷"""
    daily = _parse_daily_actions(plan)
    params = {"plan_id": plan.id}
    if action == "nurture_tick":
        params.update({
            "min_scrolls": int(daily.get("min_scrolls", 2) or 2),
            "max_scrolls": int(daily.get("max_scrolls", 5) or 5),
            "like_probability": float(daily.get("like_probability", 0.2) or 0.2),
            "follow_probability": float(daily.get("follow_probability", 0.05) or 0.05),
            "comment_probability": float(daily.get("comment_probability", 0.02) or 0.02),
            "browse_minutes": int(daily.get("browse_minutes", 2) or 2),
        })
    return {
        "type": "command",
        "action": action,
        "params": params,
        "timestamp": datetime.utcnow().isoformat(),
    }


async def _dispatch_to_plan(plan: NurturePlan, action: str) -> dict:
    """向计划内每台设备下发指令（WebSocket 直发 → HTTP 轮询队列）"""
    devices = _parse_device_ids(plan)
    if not devices:
        return {"dispatched": 0, "total": 0}
    command = _build_nurture_command(plan, action)
    dispatched = 0
    for device_id in devices:
        try:
            success, via_ws = await manager.send_or_enqueue_command(device_id, command)
            if success:
                dispatched += 1
        except Exception as e:
            logger.error(f"[nurture] dispatch {action} to {device_id} error: {e}")
    return {"dispatched": dispatched, "total": len(devices)}


def dispatch_tick_for_active_plans():
    """（供后台 scheduler 线程调用）为所有 active 计划下发 nurture_tick

    与事件循环无关：内部自建 event loop 执行 async 下发。
    """
    db = SessionLocal()
    try:
        plans = db.query(NurturePlan).filter(NurturePlan.status == "active").all()
        plan_ids = [p.id for p in plans]
    finally:
        db.close()

    if not plan_ids:
        return {"plans": 0}

    import asyncio
    dispatched_total = 0
    for plan_id in plan_ids:
        try:
            db = SessionLocal()
            try:
                plan = db.query(NurturePlan).filter(NurturePlan.id == plan_id).first()
            finally:
                db.close()
            if not plan or plan.status != "active":
                continue
            # M8: 超过 end_date 的计划标记完成并跳过
            if plan.end_date:
                from datetime import timezone
                end = plan.end_date
                if end.tzinfo is None:
                    end = end.replace(tzinfo=timezone.utc)
                if datetime.now(timezone.utc) > end:
                    plan.status = "completed"
                    db = SessionLocal()
                    try:
                        p = db.query(NurturePlan).filter(NurturePlan.id == plan.id).first()
                        if p:
                            p.status = "completed"
                            db.commit()
                    finally:
                        db.close()
                    continue
            loop = asyncio.new_event_loop()
            try:
                stats = loop.run_until_complete(_dispatch_to_plan(plan, "nurture_tick"))
            finally:
                loop.close()
            dispatched_total += stats.get("dispatched", 0)
        except Exception as e:
            logger.error(f"[nurture-scheduler] plan {plan_id} dispatch failed: {e}")
    logger.info(f"[nurture-scheduler] ticked {len(plan_ids)} plans, {dispatched_total} devices")
    return {"plans": len(plan_ids), "dispatched": dispatched_total}


# ========== CRUD ==========

@router.post("/nurture-plans/", status_code=201)
def create_nurture_plan(
    body: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """创建养号计划
    body: {name, device_ids: [机器码...], account_ids: [id...], daily_actions: {...}, start_date?, end_date?}
    """
    name = (body.get("name") or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="计划名称不能为空")

    device_ids = body.get("device_ids") or []
    if isinstance(device_ids, (list, tuple)):
        device_ids = [str(d).strip() for d in device_ids if str(d).strip()]
    else:
        device_ids = []

    # 校验目标设备归属（非admin只能操作自己的设备）
    from tenant import resolve_owned_device
    for dev_code in device_ids:
        if not resolve_owned_device(db, dev_code, current_user):
            raise HTTPException(status_code=404, detail=f"设备不存在或无权限: {dev_code}")

    account_ids = body.get("account_ids") or []
    if isinstance(account_ids, (list, tuple)):
        account_ids = [int(a) for a in account_ids if str(a).strip().isdigit()]
    else:
        account_ids = []

    daily_actions = body.get("daily_actions") or {}
    if not isinstance(daily_actions, dict):
        daily_actions = {}

    start_date = None
    if body.get("start_date"):
        try:
            start_date = datetime.fromisoformat(str(body["start_date"]).replace("Z", "+00:00"))
        except Exception:
            raise HTTPException(status_code=400, detail="start_date 格式非法，需 ISO8601")
    end_date = None
    if body.get("end_date"):
        try:
            end_date = datetime.fromisoformat(str(body["end_date"]).replace("Z", "+00:00"))
        except Exception:
            raise HTTPException(status_code=400, detail="end_date 格式非法，需 ISO8601")

    plan = NurturePlan(
        name=name,
        device_ids=json.dumps(device_ids, ensure_ascii=False),
        account_ids=json.dumps(account_ids),
        daily_actions=json.dumps(daily_actions, ensure_ascii=False),
        status="paused",
        start_date=start_date,
        end_date=end_date,
        api_id=current_user.api_id or "",
    )
    db.add(plan)
    db.commit()
    db.refresh(plan)
    return _serialize_plan(plan)


@router.get("/nurture-plans/")
def list_nurture_plans(
    status: Optional[str] = Query(None),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """查询养号计划，可按状态过滤（tenant 隔离）"""
    query = db.query(NurturePlan)
    scope = tenant_scope(NurturePlan, current_user)
    if scope is not None:
        query = query.filter(scope)
    if status:
        if status not in VALID_STATUSES:
            raise HTTPException(status_code=400, detail=f"非法状态: {status}，可选 {sorted(VALID_STATUSES)}")
        query = query.filter(NurturePlan.status == status)
    plans = query.order_by(NurturePlan.id.desc()).limit(limit).all()
    return {"count": len(plans), "results": [_serialize_plan(p) for p in plans]}


@router.delete("/nurture-plans/{plan_id}/")
def delete_nurture_plan(
    plan_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """删除养号计划"""
    plan = db.query(NurturePlan).filter(NurturePlan.id == plan_id).first()
    if not plan:
        raise HTTPException(status_code=404, detail="养号计划不存在")
    ensure_owned(plan, current_user)
    db.delete(plan)
    db.commit()
    return {"message": "删除成功"}


# ========== 开始 / 暂停 ==========

@router.post("/nurture-plans/{plan_id}/start/")
async def start_nurture_plan(
    plan_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """激活养号计划并立即向每台设备下发 nurture_tick"""
    plan = db.query(NurturePlan).filter(NurturePlan.id == plan_id).first()
    if not plan:
        raise HTTPException(status_code=404, detail="养号计划不存在")
    ensure_owned(plan, current_user)

    plan.status = "active"
    db.commit()

    stats = await _dispatch_to_plan(plan, "nurture_tick")
    return {
        "success": True,
        "message": f"养号计划已激活，已向 {stats['dispatched']}/{stats['total']} 台设备下发 nurture_tick",
        "plan_id": plan.id,
        "status": plan.status,
        "dispatched": stats["dispatched"],
        "total": stats["total"],
    }


@router.post("/nurture-plans/{plan_id}/pause/")
async def pause_nurture_plan(
    plan_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """暂停养号计划并向每台设备下发 nurture_stop"""
    plan = db.query(NurturePlan).filter(NurturePlan.id == plan_id).first()
    if not plan:
        raise HTTPException(status_code=404, detail="养号计划不存在")
    ensure_owned(plan, current_user)

    plan.status = "paused"
    db.commit()

    stats = await _dispatch_to_plan(plan, "nurture_stop")
    return {
        "success": True,
        "message": f"养号计划已暂停，已向 {stats['dispatched']}/{stats['total']} 台设备下发 nurture_stop",
        "plan_id": plan.id,
        "status": plan.status,
        "dispatched": stats["dispatched"],
        "total": stats["total"],
    }
