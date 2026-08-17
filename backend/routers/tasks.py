import json
from datetime import datetime

from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session

from database import get_db
from models.task import Task
from schemas.task import TaskResponse, TaskCreateRequest, TaskStartRequest
from schemas.common import PaginatedResponse, MessageResponse
from dependencies import get_current_user
from models.user import User
from tenant import tenant_scope, ensure_owned, resolve_owned_device
from task_engine import TASK_TYPE_ACTIONS, RISK_CAP_DEFAULTS, UNIT_PARAM_DEFAULTS

router = APIRouter(prefix="/api/biz/v2", tags=["tasks"])


def _task_to_dict(task: Task) -> dict:
    """ORM -> dict，解析 config JSON"""
    d = {
        "id": task.id,
        "name": task.name or "",
        "type": task.type or "",
        "status": task.status or "",
        "target": task.target or "",
        "device": task.device or "",
        "account": task.account or "",
        "progress": task.progress or 0,
        "created_at": task.created_at,
        "finished_at": task.finished_at,
        "config": json.loads(task.config or "{}"),
        "total": task.total or 0,
        "done": task.done or 0,
        "fail_count": task.fail_count or 0,
        "last_log": task.last_log or "",
        "error": task.error or "",
        "started_at": task.started_at,
        "next_dispatch_at": task.next_dispatch_at,
    }
    return d


@router.get("/tasks/", response_model=PaginatedResponse)
def list_tasks(
    status: str = Query(None),
    type: str = Query(None),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(Task)
    scope = tenant_scope(Task, current_user)
    if scope is not None:
        query = query.filter(scope)
    if status:
        query = query.filter(Task.status == status)
    if type:
        query = query.filter(Task.type == type)
    total = query.count()
    tasks = (
        query.order_by(Task.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return PaginatedResponse(
        count=total,
        results=[_task_to_dict(t) for t in tasks],
    )


@router.post("/tasks/", response_model=TaskResponse, status_code=201)
def create_task(
    req: TaskCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    config = req.config or {}
    # 兼容旧前端：count 字符串 -> total
    targets = config.get("targets") or []
    total = 0
    if config.get("count"):
        total = int(config["count"])
    elif targets:
        total = len(targets)
    elif req.count:
        total = int(req.count)

    # 安全：非 admin 创建任务时，校验所有下发设备归属（防跨租户注入指令）
    if current_user.role != "admin":
        device_names = set()
        if req.device:
            device_names.add(req.device)
        for dn in (config.get("device_ids") or []):
            if dn:
                device_names.add(dn)
        for dn in device_names:
            if not resolve_owned_device(db, dn, current_user):
                raise HTTPException(status_code=403, detail=f"无权对设备 {dn} 下发任务")

    # 风控钳制（PPT 参考：点赞≤300/号，关注≤200/号）
    risk_cap = config.get("risk_cap")
    if risk_cap is None:
        risk_cap = RISK_CAP_DEFAULTS.get(req.type, 0)
    if risk_cap and total > risk_cap:
        total = risk_cap

    action = config.get("action") or TASK_TYPE_ACTIONS.get(req.type, req.type)
    name = req.name or f"{req.type}任务"
    if targets:
        name += f"-{len(targets)}目标"

    task = Task(
        type=req.type,
        target=req.target,
        device=req.device,
        account=req.account,
        name=name,
        status="pending",
        progress=0,
        config=json.dumps({**config, "action": action}),
        total=total or 0,
        done=0,
        fail_count=0,
        last_log="[INFO] 任务已创建，待启动",
    )
    if current_user.role != "admin":
        task.api_id = current_user.api_id or ""
    db.add(task)
    db.commit()
    db.refresh(task)
    return _task_to_dict(task)


@router.get("/tasks/status/running/", response_model=PaginatedResponse)
def list_running_tasks(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """运行中任务（手机端运行监控卡片订阅：进度/最近日志/停止操作）"""
    query = db.query(Task).filter(Task.status == "running")
    scope = tenant_scope(Task, current_user)
    if scope is not None:
        query = query.filter(scope)
    tasks = query.order_by(Task.created_at.asc()).limit(50).all()
    return PaginatedResponse(
        count=len(tasks),
        results=[_task_to_dict(t) for t in tasks],
    )


def _resolve_targets(db, task, config, req: TaskStartRequest):
    """解析目标池：config.targets 优先，否则从采集数据分组解析（数据组引用）"""
    targets = config.get("targets") or []
    if targets:
        return targets
    group = req.target_group or config.get("target_group") or ""
    if not group:
        return []
    from models.collected_data import CollectedData
    query = db.query(CollectedData).filter(CollectedData.group_name == group)
    if task.api_id:
        query = query.filter(CollectedData.api_id == task.api_id)
    rows = query.limit(2000).all()
    # 数据组单元：优先 aweme_id，否则 author
    return [r.aweme_id or r.author for r in rows if (r.aweme_id or r.author)]


@router.post("/tasks/{task_id}/start/", response_model=MessageResponse)
def start_task(
    task_id: int,
    req: TaskStartRequest = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """启动引擎任务：解析目标池 -> running -> 引擎接管"""
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="任务不存在")
    ensure_owned(task, current_user)
    if task.status == "running":
        return MessageResponse(message="任务已在运行")

    req = req or TaskStartRequest()
    config = json.loads(task.config or "{}")
    targets = _resolve_targets(db, task, config, req)

    if not targets:
        raise HTTPException(status_code=400, detail="无可执行目标（请提供 targets 或数据组 target_group）")

    count = req.count or config.get("count") or 0
    total = int(count) if count else len(targets)
    # 风控钳制
    risk_cap = config.get("risk_cap")
    if risk_cap is None:
        risk_cap = RISK_CAP_DEFAULTS.get(task.type, 0)
    if risk_cap and total > risk_cap:
        total = risk_cap

    task.config = json.dumps({**config, "targets": targets})
    task.total = total
    task.done = 0
    task.fail_count = 0
    task.progress = 0
    task.status = "running"
    task.started_at = datetime.utcnow()
    task.next_dispatch_at = datetime.utcnow()  # 立即下发第一单元
    task.last_log = f"[INFO] 任务启动，共 {total} 单元"
    task.error = ""
    db.commit()
    return MessageResponse(message=f"任务已启动（{total} 单元，目标组 {req.target_group or '自定义'}）")


@router.post("/tasks/{task_id}/stop/", response_model=MessageResponse)
def stop_task(
    task_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="任务不存在")
    ensure_owned(task, current_user)
    task.status = "stopped"
    task.finished_at = datetime.utcnow()
    task.last_log = f"[WARN] 已停止（完成 {task.done}/{task.total}）"
    db.commit()
    return MessageResponse(message=f"任务已停止（已下发 {task.done}/{task.total}）")


@router.post("/tasks/{task_id}/pause/", response_model=MessageResponse)
def pause_task(
    task_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="任务不存在")
    ensure_owned(task, current_user)
    if task.status == "running":
        task.status = "paused"
        task.last_log = "[WARN] 已暂停"
        db.commit()
        return MessageResponse(message="任务已暂停")
    return MessageResponse(message=f"任务当前状态 {task.status}，无需暂停")


@router.post("/tasks/{task_id}/resume/", response_model=MessageResponse)
def resume_task(
    task_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="任务不存在")
    ensure_owned(task, current_user)
    if task.status == "paused" or task.status == "stopped":
        task.status = "running"
        task.next_dispatch_at = datetime.utcnow()
        task.last_log = "[INFO] 已恢复"
        db.commit()
        return MessageResponse(message="任务已恢复")
    return MessageResponse(message=f"任务当前状态 {task.status}，无法恢复")
