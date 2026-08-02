"""定时任务调度器 — 简单 cron 匹配，每分钟检查并派发指令

不依赖 APScheduler。cron 格式: "分 时 日 月 周"（* 或 数字 或 a-b 范围）。
"""
import json
import logging
import threading
from datetime import datetime

from database import SessionLocal
from models.timed_task import TimedTask

logger = logging.getLogger(__name__)

# ---- 简单 cron 匹配 ----
def _parse_field(field: str, lo: int, hi: int):
    """解析 cron 字段，返回允许值集合。支持 *、数字、a-b、a-b/c、逗号"""
    allowed = set()
    for part in field.split(","):
        part = part.strip()
        if part == "*":
            allowed.update(range(lo, hi + 1))
            continue
        if "/" in part:
            base, step = part.split("/", 1)
            step = int(step)
            if base == "*":
                allowed.update(range(lo, hi + 1, step))
            elif "-" in base:
                a, b = map(int, base.split("-"))
                allowed.update(range(a, b + 1, step))
            continue
        if "-" in part:
            a, b = map(int, part.split("-"))
            allowed.update(range(a, b + 1))
        else:
            allowed.add(int(part))
    return allowed


def cron_matches(cron: str, now: datetime) -> bool:
    """判断当前时间是否匹配 cron 表达式。cron: "分 时 日 月 周" """
    try:
        parts = cron.split()
        if len(parts) != 5:
            return False
        minute, hour, dom, month, dow = parts
        if now.minute not in _parse_field(minute, 0, 59): return False
        if now.hour not in _parse_field(hour, 0, 23): return False
        if now.day not in _parse_field(dom, 1, 31): return False
        if now.month not in _parse_field(month, 1, 12): return False
        if now.isoweekday() not in _parse_field(dow, 1, 7): return False
        return True
    except Exception:
        return False


# ---- 调度循环 ----
_scheduler_stop = threading.Event()
_scheduler_thread = None


def _dispatch_task(t: TimedTask):
    """向定时任务的目标设备派发指令"""
    try:
        from connection_manager import manager
        import asyncio
        device_ids = json.loads(t.device_ids or "[]") if t.device_ids else []
        action = t.action or "check_health"
        params = json.loads(t.params or "{}") if t.params else {}
        command = {
            "type": "command",
            "action": action,
            "params": params,
            "timestamp": datetime.utcnow().isoformat(),
        }
        dispatched = 0
        for device_id in device_ids:
            if not isinstance(device_id, str) or not device_id:
                continue
            try:
                loop = asyncio.new_event_loop()
                try:
                    ok, via_ws = loop.run_until_complete(
                        manager.send_or_enqueue_command(device_id, command)
                    )
                    if ok:
                        dispatched += 1
                finally:
                    loop.close()
            except Exception as e:
                logger.error(f"[timed] dispatch {action} to {device_id} error: {e}")
        logger.info(f"[timed] '{t.name}' fired: {action} → {dispatched}/{len(device_ids)} devices")
    except Exception as e:
        logger.error(f"[timed] task {t.id} dispatch error: {e}")


def _scheduler_loop():
    logger.info("[timed-scheduler] started")
    last_checked = None
    while not _scheduler_stop.is_set():
        try:
            now = datetime.now()
            # 每分钟检查一次（秒对齐，避免同分钟重复触发）
            if last_checked is None or (now.year, now.month, now.day, now.hour, now.minute) != last_checked:
                last_checked = (now.year, now.month, now.day, now.hour, now.minute)
                db = SessionLocal()
                try:
                    tasks = db.query(TimedTask).filter(TimedTask.enabled == True).all()
                    for t in tasks:
                        if cron_matches(t.cron, now):
                            t.last_run = now
                            db.commit()
                            _dispatch_task(t)
                finally:
                    db.close()
        except Exception as e:
            logger.error(f"[timed-scheduler] error: {e}")
        _scheduler_stop.wait(15)


def start_scheduler():
    global _scheduler_thread
    if _scheduler_thread is not None and _scheduler_thread.is_alive():
        return
    _scheduler_thread = threading.Thread(target=_scheduler_loop, daemon=True, name="timed-scheduler")
    _scheduler_thread.start()


def stop_scheduler():
    _scheduler_stop.set()
