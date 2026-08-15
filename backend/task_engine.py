"""统一任务引擎 — 后台调度线程

职责：把 running 状态的引擎任务按"随机间隔 + 风控上限"逐单元下发到设备。
- 每 N 秒 tick 一次，处理到期（next_dispatch_at <= now）的 running 任务
- 单任务：pending -> running(引擎接管) -> 逐单元下发 -> done
- 下发 payload: {"type":"command","action":<action>,"params":{...静态params, <unit_param>: 当前单元}}
- 进度: done/total，last_log 记录最近一步（手机端监控卡片读这里）
- 风控: like/comment_like/follow/follow_back 类总单元数被 risk_cap 钳制
"""

import asyncio
import json
import logging
import random
import threading
from datetime import datetime, timedelta

from sqlalchemy import or_

logger = logging.getLogger(__name__)

_TICK_INTERVAL = 3  # 秒

# 任务类型 -> 默认设备 action（config.action 可覆盖）
TASK_TYPE_ACTIONS = {
    "like": "like",
    "comment_like": "comment_like",
    "follow": "follow",
    "follow_back": "follow",
    "comment": "comment",
    "dm": "send_dm",
    "post_video": "post_video",
    "collect": "collect_fans",
    "batch_follow": "batch_follow",
    "batch_like": "batch_like",
    "batch_comment": "batch_comment",
    "smart_browse": "smart_browse",
}

# 风控类型 -> 默认上限（PPT 参考：点赞推荐 ≤300/号）
RISK_CAP_DEFAULTS = {
    "like": 300,
    "comment_like": 300,
    "follow": 200,
    "follow_back": 200,
}

# 单元参数名：每种类型把"当前单元"放进 params 的哪个字段
# 默认 target（大多数命令读 params.target/username/uid）
UNIT_PARAM_DEFAULTS = {
    "comment": "text",        # 单元 = 评论文本
    "dm": "content",          # 单元 = 私信内容
    "post_video": "video_url",  # 单元 = 视频URL
}


class TaskEngine:
    def __init__(self):
        self._stop = threading.Event()
        self._thread = None

    # ---------- 生命周期 ----------
    def start(self):
        if self._thread is not None and self._thread.is_alive():
            return
        self._thread = threading.Thread(target=self._loop, daemon=True, name="task-engine")
        self._thread.start()
        logger.info("[task-engine] started")

    def stop(self):
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=3)

    def _loop(self):
        while not self._stop.is_set():
            try:
                self._tick()
            except Exception as e:
                logger.error(f"[task-engine] tick error: {e}")
            self._stop.wait(_TICK_INTERVAL)

    # ---------- 主循环 ----------
    def _tick(self):
        from database import SessionLocal
        from models.task import Task

        db = SessionLocal()
        try:
            now = datetime.utcnow()
            due = (
                db.query(Task)
                .filter(
                    Task.status == "running",
                    or_(
                        Task.next_dispatch_at.is_(None),
                        Task.next_dispatch_at <= now,
                    ),
                )
                .order_by(Task.created_at.asc())
                .all()
            )
            for task in due:
                try:
                    self._dispatch_one(db, task, now)
                except Exception as e:
                    task.error = f"dispatch error: {e}"
                    task.last_log = f"❌ 下发异常: {e}"
                    logger.error(f"[task-engine] task {task.id} dispatch error: {e}")
            db.commit()
        finally:
            db.close()

    # ---------- 单任务下发 ----------
    def _dispatch_one(self, db, task, now):
        config = json.loads(task.config or "{}")
        targets = config.get("targets") or []
        total = task.total or len(targets) or 0
        if total <= 0 or not targets:
            # 远程指令（route 即时下发，config 为空、无 targets）→ 不判失败：
            # 已由 /command/ 路由直接下发，等设备 WS 结果回填状态（done/success）。
            # 旧逻辑在此直接判 failed → 连成功执行的 like/open_search 都显示"无有效目标单元"（任务状态误报根因）
            if not task.config and not config.get("action"):
                return
            task.status = "failed"
            task.error = "无有效目标单元"
            task.last_log = "❌ 无有效目标，任务失败"
            task.finished_at = now
            return

        # 已完成全部 -> done
        if task.done >= total:
            task.status = "done"
            task.progress = 100
            task.finished_at = now
            task.last_log = "✅ 任务完成"
            return

        # 取当前单元（targets 循环复用）
        unit = targets[task.done % len(targets)]

        # 取下发设备（device_ids 轮询）
        device_ids = config.get("device_ids") or ([task.device] if task.device else [])
        if not device_ids:
            task.status = "failed"
            task.error = "未指定设备"
            task.last_log = "❌ 未指定设备，任务失败"
            task.finished_at = now
            return
        device = device_ids[task.done % len(device_ids)]

        # 组装 payload
        action = config.get("action") or TASK_TYPE_ACTIONS.get(task.type, task.type)
        unit_param = config.get("unit_param") or UNIT_PARAM_DEFAULTS.get(task.type, "target")
        params = dict(config.get("params") or {})
        params[unit_param] = unit

        # 下发（async 通道：WS 直发 / HTTP 轮询入队）
        from connection_manager import manager
        loop = asyncio.new_event_loop()
        try:
            _, via_ws = loop.run_until_complete(
                manager.send_or_enqueue_command(device, {
                    "type": "command",
                    "action": action,
                    "params": params,
                })
            )
        finally:
            loop.close()

        # 更新进度
        task.done += 1
        task.progress = int(task.done / total * 100)
        interval = self._rand_interval(config)
        task.next_dispatch_at = now + timedelta(seconds=interval)
        task.last_log = f"📤 {task.done}/{total} {action}→{unit} (设备{device})"
        task.account = task.account or device

        # 写执行记录（审计）
        from models.task_execution import TaskExecution
        db.add(TaskExecution(
            api_id=task.api_id,
            task_name=task.name or f"{task.type}任务",
            type=task.type,
            status="dispatched",
            device=device,
            account=task.account or "",
            target=str(unit),
            result=f"action={action}" + (" via_ws" if via_ws else " queued"),
            started_at=now,
            created_at=now,
        ))

        # 完成判定
        if task.done >= total:
            task.status = "done"
            task.progress = 100
            task.finished_at = now
            task.last_log = "✅ 任务完成"

    @staticmethod
    def _rand_interval(config) -> int:
        lo = max(1, int(config.get("min_interval") or 3))
        hi = max(lo, int(config.get("max_interval") or 8))
        return random.randint(lo, hi)


# 全局单例
engine = TaskEngine()


def start_task_engine():
    engine.start()


def stop_task_engine():
    engine.stop()
