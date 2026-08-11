from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import os, mimetypes
import threading
import logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

from config import settings
from database import engine, Base

logger = logging.getLogger(__name__)

# 导入所有模型确保注册 (these will be created in Task 2, but we import them now)
from models.user import User
from models.device import DeviceBinding
from models.group import DeviceGroup
from models.account import Account
from models.task import Task
from models.task_execution import TaskExecution
from models.timed_task import TimedTask
from models.feedback import Feedback
from models.announcement import Announcement
from models.reply_template import ReplyTemplate
from models.media import Media
from models.collected_data import CollectedData
from models.material import MaterialGroup, Material
from models.video_post import VideoPost
from models.dm_task import DmTask
from models.nurture_plan import NurturePlan
from models.quick_command import QuickCommand
from models.license import License
from models.udid_request import UDIDRequest
from models.public_user import PublicUser
from models.proxy_node import ProxyNode

# 创建表
Base.metadata.create_all(bind=engine)

app = FastAPI(title="XNOW Cloud Control API", version="1.3.0")

# M7: CORS 收紧 — 认证用 Bearer header(非cookie)，不需 credentials
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 注册路由
from routers import auth, dashboard, devices, accounts, tasks, task_executions
from routers import timed_tasks, feedback, announcements, reply_templates
from routers import media, collected_data, execution_stats
from routers import materials, video_posts
from routers import dm_tasks
from routers import nurture, quick_commands
from routers import licenses
from routers import udid
from routers import ws as ws_router
from routers import device_commands
from routers import public_users
from routers import proxy_nodes
from routers import translate

app.include_router(auth.router)
app.include_router(dashboard.router)
app.include_router(devices.router)
app.include_router(accounts.router)
app.include_router(tasks.router)
app.include_router(task_executions.router)
app.include_router(timed_tasks.router)
app.include_router(feedback.router)
app.include_router(announcements.router)
app.include_router(reply_templates.router)
app.include_router(media.router)
app.include_router(collected_data.router)
app.include_router(execution_stats.router)
app.include_router(materials.router)
app.include_router(video_posts.router)
app.include_router(dm_tasks.router)
app.include_router(nurture.router)
app.include_router(quick_commands.router)
app.include_router(licenses.router)
app.include_router(udid.router)
app.include_router(ws_router.router)
app.include_router(device_commands.router)
app.include_router(public_users.router)
app.include_router(proxy_nodes.router)
app.include_router(translate.router)

@app.get("/api/health")
def health():
    return {"status": "ok", "version": "1.3.0"}

# 提供上传文件访问
os.makedirs(settings.UPLOAD_DIR, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=settings.UPLOAD_DIR), name="uploads")

# 前端 SPA — 构建产物在 backend/static/
mimetypes.add_type("text/javascript", ".js")
mimetypes.add_type("text/css", ".css")
static_dir = os.path.join(os.path.dirname(__file__), "static")
os.makedirs(static_dir, exist_ok=True)

# 在所有 API 路由之后注册 SPA 兜底
# 非 API 路径一律返回 index.html（由前端 router 处理）
@app.get("/{full_path:path}")
async def serve_spa(full_path: str):
    # API 路径不由这里处理
    if full_path.startswith("api/") or full_path.startswith("uploads/") or full_path.startswith("ws/"):
        from fastapi.responses import JSONResponse
        return JSONResponse(status_code=404, content={"detail": "Not found"})

    # 根路径 → 返回 SPA 首页（nginx 代理 / 到后端，空路径应回 index.html）
    if not full_path:
        return FileResponse(os.path.join(static_dir, "index.html"))

    # 防路径穿越：拒绝任何含 ../ 或绝对路径的请求
    if ".." in full_path or full_path.startswith("/") or "\\" in full_path:
        from fastapi.responses import JSONResponse
        return JSONResponse(status_code=404, content={"detail": "Not found"})

    file_path = os.path.abspath(os.path.join(static_dir, full_path))
    # M10: 确保解析后的路径仍在 static 目录内（commonpath 路径分量校验）
    try:
        if os.path.commonpath([file_path, os.path.abspath(static_dir)]) != os.path.abspath(static_dir):
            from fastapi.responses import JSONResponse
            return JSONResponse(status_code=404, content={"detail": "Not found"})
    except ValueError:
        from fastapi.responses import JSONResponse
        return JSONResponse(status_code=404, content={"detail": "Not found"})

    if not os.path.exists(file_path) or os.path.isdir(file_path):
        file_path = os.path.join(static_dir, "index.html")
    return FileResponse(file_path)


# ========== 养号计划后台调度线程 ==========
# 每 N 秒为所有 active 养号计划下发 nurture_tick（不阻塞事件循环）。
# 下发通过 connection_manager.send_or_enqueue_command（WebSocket 直发 → HTTP 轮询队列）。
_NURTURE_TICK_INTERVAL = 30 * 60  # 30 分钟

_nurture_scheduler_stop = threading.Event()
_nurture_scheduler_thread = None

# ---- 设备离线巡检（H9） ----
_OFFLINE_SWEEP_INTERVAL = 15  # 秒
_offline_sweep_stop = threading.Event()
_offline_sweep_thread = None


def _offline_sweep_loop():
    """HTTP 轮询设备掉线标记：last_online 超过 35s 未更新 → is_online=False"""
    logger.info("[offline-sweep] started")
    from datetime import datetime, timedelta
    while not _offline_sweep_stop.is_set():
        try:
            from database import SessionLocal
            from models.device import DeviceBinding
            db = SessionLocal()
            try:
                cutoff = datetime.utcnow() - timedelta(seconds=120)
                from sqlalchemy import or_
                stale = db.query(DeviceBinding).filter(
                    DeviceBinding.is_online == True,
                    or_(
                        DeviceBinding.last_online < cutoff,
                        DeviceBinding.last_online.is_(None),
                    ),
                ).all()
                for d in stale:
                    d.is_online = False
                    d.online = False
                    d.status = "offline"
                if stale:
                    db.commit()
                    logger.info(f"[offline-sweep] marked {len(stale)} devices offline")
            finally:
                db.close()
        except Exception as e:
            logger.error(f"[offline-sweep] error: {e}")
        _offline_sweep_stop.wait(_OFFLINE_SWEEP_INTERVAL)


def _start_offline_sweep():
    global _offline_sweep_thread
    if _offline_sweep_thread is not None and _offline_sweep_thread.is_alive():
        return
    _offline_sweep_thread = threading.Thread(
        target=_offline_sweep_loop,
        daemon=True,
        name="offline-sweep",
    )
    _offline_sweep_thread.start()


def _nurture_scheduler_loop():
    logger.info("[nurture-scheduler] started")
    while not _nurture_scheduler_stop.is_set():
        try:
            # 延迟导入，避免启动时循环依赖
            from routers.nurture import dispatch_tick_for_active_plans
            dispatch_tick_for_active_plans()
        except Exception as e:
            logger.error(f"[nurture-scheduler] tick error: {e}")
        _nurture_scheduler_stop.wait(_NURTURE_TICK_INTERVAL)


def _start_nurture_scheduler():
    global _nurture_scheduler_thread
    if _nurture_scheduler_thread is not None and _nurture_scheduler_thread.is_alive():
        return
    _nurture_scheduler_thread = threading.Thread(
        target=_nurture_scheduler_loop,
        daemon=True,
        name="nurture-scheduler",
    )
    _nurture_scheduler_thread.start()


_start_nurture_scheduler()
_start_offline_sweep()

# 统一任务引擎：运行中任务逐单元下发（随机间隔+风控上限）
from task_engine import start_task_engine as _start_task_engine, stop_task_engine as _stop_task_engine
_start_task_engine()

# 优化2: 定时任务调度器（每分钟检查 cron 并派发）
from timed_scheduler import start_scheduler as _start_timed_scheduler, stop_scheduler as _stop_timed_scheduler
_start_timed_scheduler()


@app.on_event("shutdown")
def _shutdown_background_threads():
    """应用关闭时通知后台线程退出（养号调度 + 离线巡检 + 定时任务）"""
    _nurture_scheduler_stop.set()
    _offline_sweep_stop.set()
    _stop_timed_scheduler()
    _stop_task_engine()
    if _nurture_scheduler_thread is not None:
        _nurture_scheduler_thread.join(timeout=3)
    if _offline_sweep_thread is not None:
        _offline_sweep_thread.join(timeout=3)
