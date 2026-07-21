from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import os, mimetypes

from config import settings
from database import engine, Base

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

# 创建表
Base.metadata.create_all(bind=engine)

app = FastAPI(title="XNOW Cloud Control API", version="1.2.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 注册路由
from routers import auth, dashboard, devices, accounts, tasks, task_executions
from routers import timed_tasks, feedback, announcements, reply_templates
from routers import media, collected_data, execution_stats
from routers import ws as ws_router
from routers import device_commands

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
app.include_router(ws_router.router)
app.include_router(device_commands.router)

@app.get("/api/health")
def health():
    return {"status": "ok", "version": "1.2.0"}

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
    file_path = os.path.join(static_dir, full_path)
    if not os.path.exists(file_path) or os.path.isdir(file_path):
        file_path = os.path.join(static_dir, "index.html")
    return FileResponse(file_path)
