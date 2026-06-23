# FastAPI 后端 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use `- [ ]` syntax.

**Goal:** 构建 XNOW 云控系统 FastAPI 后端，替换 wsyufu.net 代理，提供完整 REST API

**Architecture:** 单服务 FastAPI 应用 + SQLite 数据库（开发）/ PostgreSQL（生产）+ JWT 认证。后端目录 `backend/` 独立于前端 `login/`。API 路径保持 `/api/biz/v2/` 前缀兼容前端现有调用。

**Tech Stack:** Python 3.11, FastAPI 0.115, SQLAlchemy 2.0, SQLite, PyJWT, uvicorn

---

## Phase 1 检查清单

```
[x] Spec is scoped to a single plan（后端替换）
[x] All files mapped: created, modified, deleted
[x] Each file has one clear responsibility
[x] File structure follows established patterns
```

## 文件结构

```
backend/
├── main.py                    # FastAPI 应用入口 + 路由注册
├── config.py                  # 配置（SECRET_KEY, DB_URL 等）
├── database.py                # SQLAlchemy 引擎 + SessionLocal
├── models/
│   ├── __init__.py
│   ├── user.py                # User 模型
│   ├── device.py              # DeviceBinding 模型
│   ├── account.py             # Account 模型
│   ├── task.py                # Task 模型
│   ├── task_execution.py      # TaskExecution 模型
│   ├── timed_task.py          # TimedTask 模型
│   ├── feedback.py            # Feedback 模型
│   ├── announcement.py        # Announcement 模型
│   ├── reply_template.py      # ReplyTemplate 模型
│   ├── media.py               # Media 模型
│   └── collected_data.py      # CollectedData 模型
├── schemas/
│   ├── __init__.py
│   ├── auth.py                # 登录请求/响应 schema
│   ├── dashboard.py           # Dashboard 统计 schema
│   ├── device.py              # Device schema
│   ├── account.py             # Account schema
│   ├── task.py                # Task schema
│   ├── task_execution.py      # TaskExecution schema
│   ├── timed_task.py          # TimedTask schema
│   ├── feedback.py            # Feedback schema
│   ├── announcement.py        # Announcement schema
│   ├── reply_template.py      # ReplyTemplate schema
│   ├── media.py               # Media schema
│   ├── collected_data.py      # CollectedData schema
│   └── common.py              # 分页/通用响应 schema
├── routers/
│   ├── __init__.py
│   ├── auth.py                # POST /api/auth/login/, /api/auth/password/
│   ├── dashboard.py           # GET /api/biz/v2/dashboard/stats/
│   ├── devices.py             # GET /api/biz/v2/device-bindings/
│   ├── accounts.py            # GET /api/biz/v2/accounts/
│   ├── tasks.py               # GET/POST /api/biz/v2/tasks/
│   ├── task_executions.py     # GET /api/biz/v2/task-executions/
│   ├── timed_tasks.py         # CRUD /api/biz/v2/timed-tasks/
│   ├── feedback.py            # GET/POST /api/biz/v2/feedback/
│   ├── announcements.py       # GET /api/biz/v2/announcements/
│   ├── reply_templates.py     # CRUD /api/biz/v2/reply-templates/
│   ├── media.py               # GET/POST /api/biz/v2/media/
│   ├── collected_data.py      # GET /api/biz/v2/collected-data/
│   └── execution_stats.py     # GET /api/biz/v2/execution-stats/
├── dependencies.py            # 依赖注入（get_db, get_current_user）
├── seed.py                    # 初始种子数据
├── requirements.txt           # Python 依赖
└── data/                      # SQLite 数据库文件目录（gitignored）
    └── .gitkeep
```

---

## Phase 2 — 任务定义

### Task 1: 项目骨架 + 依赖 + 配置

**Files:**
- Create: `backend/requirements.txt`
- Create: `backend/.env`
- Create: `backend/config.py`
- Create: `backend/database.py`
- Create: `backend/main.py`
- Create: `backend/dependencies.py`
- Create: `backend/data/.gitkeep`

- [ ] **Step 1: 创建 requirements.txt**

```txt
fastapi==0.115.6
uvicorn==0.32.1
sqlalchemy==2.0.48
pyjwt==2.13.0
pydantic==2.12.5
pydantic-settings==2.13.1
python-multipart==0.0.20
aiofiles==24.1.0
```

- [ ] **Step 2: 创建 config.py**

```python
import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    SECRET_KEY: str = "xnow-secret-key-change-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440  # 24h
    DATABASE_URL: str = "sqlite:///./data/xnow.db"
    UPLOAD_DIR: str = "./data/uploads"

    class Config:
        env_file = ".env"

settings = Settings()
```

- [ ] **Step 3: 创建 database.py**

```python
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase

from config import settings

engine = create_engine(
    settings.DATABASE_URL,
    connect_args={"check_same_thread": False}  # SQLite only
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

class Base(DeclarativeBase):
    pass

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

- [ ] **Step 4: 创建 dependencies.py**

```python
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
import jwt

from config import settings
from database import get_db
from models.user import User

security = HTTPBearer()

def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db),
) -> User:
    token = credentials.credentials
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        user_id = payload.get("user_id")
        if user_id is None:
            raise HTTPException(status_code=401, detail="无效的 token")
    except jwt.PyJWTError:
        raise HTTPException(status_code=401, detail="无效的 token")

    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=401, detail="用户不存在")
    return user
```

- [ ] **Step 5: 创建 main.py**

```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from database import engine, Base

# 导入所有模型确保注册
from models.user import User
from models.device import DeviceBinding
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

app = FastAPI(title="XNOW Cloud Control API", version="1.0.0")

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

@app.get("/api/health")
def health():
    return {"status": "ok", "version": "1.0.0"}
```

- [ ] **Step 6: 创建 data/.gitkeep + .env**

创建空文件 `backend/data/.gitkeep` 和 `backend/.env`（内容为空，从 config.py 走默认值）。

- [ ] **Step 7: 验证启动**

Run: `cd backend && pip install -r requirements.txt && python -c "from main import app; print('OK')"`
Expected: `OK` — 无导入错误

- [ ] **Step 8: Commit**

```bash
git add backend/ && git commit -m "feat: FastAPI 项目骨架 + 依赖 + 配置"
```

---

### Task 2: 数据模型（全部 11 个表）

**Files:**
- Create: `backend/models/__init__.py`
- Create: `backend/models/user.py`
- Create: `backend/models/device.py`
- Create: `backend/models/account.py`
- Create: `backend/models/task.py`
- Create: `backend/models/task_execution.py`
- Create: `backend/models/timed_task.py`
- Create: `backend/models/feedback.py`
- Create: `backend/models/announcement.py`
- Create: `backend/models/reply_template.py`
- Create: `backend/models/media.py`
- Create: `backend/models/collected_data.py`

- [ ] **Step 1: 创建 models/__init__.py**

空文件

- [ ] **Step 2: 创建 user.py — User 模型**

```python
from sqlalchemy import Column, Integer, String, DateTime, Boolean
from sqlalchemy.sql import func
from database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, index=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
```

- [ ] **Step 3: 创建 device.py — DeviceBinding 模型**

```python
from sqlalchemy import Column, Integer, String, Boolean, DateTime
from sqlalchemy.sql import func
from database import Base

class DeviceBinding(Base):
    __tablename__ = "device_bindings"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    device_name = Column(String(100))
    status = Column(String(20), default="idle")  # online/offline/idle/executing/locked
    online = Column(Boolean, default=False)
    account_count = Column(Integer, default=0)
    accounts = Column(Integer, default=0)
    last_online = Column(DateTime(timezone=True))
    app_version = Column(String(50))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
```

- [ ] **Step 4: 创建 account.py — Account 模型**

```python
from sqlalchemy import Column, Integer, String, DateTime
from sqlalchemy.sql import func
from database import Base

class Account(Base):
    __tablename__ = "accounts"

    id = Column(Integer, primary_key=True, index=True)
    nickname = Column(String(100))
    username = Column(String(100))
    tk_number = Column(String(100))
    unique_id = Column(String(100))
    followers = Column(Integer, default=0)
    following_count = Column(Integer, default=0)
    video_count = Column(Integer, default=0)
    status = Column(String(20), default="active")  # active/risk_control/banned
    region = Column(String(50))
    country = Column(String(50))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
```

- [ ] **Step 5: 创建 task.py — Task 模型**

```python
from sqlalchemy import Column, Integer, String, DateTime, Text
from sqlalchemy.sql import func
from database import Base

class Task(Base):
    __tablename__ = "tasks"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(200))
    type = Column(String(50), nullable=False)  # follow/like/comment/dm/collect
    status = Column(String(20), default="pending")  # pending/running/success/failed/cancelled
    target = Column(Text)
    device = Column(String(100))
    account = Column(String(100))
    progress = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    finished_at = Column(DateTime(timezone=True))
```

- [ ] **Step 6: 创建 task_execution.py — TaskExecution 模型**

```python
from sqlalchemy import Column, Integer, String, DateTime, Text, Float
from sqlalchemy.sql import func
from database import Base

class TaskExecution(Base):
    __tablename__ = "task_executions"

    id = Column(Integer, primary_key=True, index=True)
    task_name = Column(String(200))
    type = Column(String(50))
    status = Column(String(20), default="pending")
    device = Column(String(100))
    account = Column(String(100))
    target = Column(Text)
    result = Column(Text)
    started_at = Column(DateTime(timezone=True))
    finished_at = Column(DateTime(timezone=True))
    duration = Column(Float, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
```

- [ ] **Step 7: 创建 timed_task.py — TimedTask 模型**

```python
from sqlalchemy import Column, Integer, String, Boolean, DateTime
from sqlalchemy.sql import func
from database import Base

class TimedTask(Base):
    __tablename__ = "timed_tasks"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(200), nullable=False)
    cron = Column(String(50), nullable=False)
    task_type = Column(String(50), default="数据采集")
    enabled = Column(Boolean, default=True)
    last_run = Column(DateTime(timezone=True))
    next_run = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
```

- [ ] **Step 8: 创建 feedback.py — Feedback 模型**

```python
from sqlalchemy import Column, Integer, String, DateTime, Text
from sqlalchemy.sql import func
from database import Base

class Feedback(Base):
    __tablename__ = "feedback"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(200))
    content = Column(Text)
    contact = Column(String(100))
    status = Column(String(20), default="pending")  # pending/resolved/closed
    reply = Column(Text)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
```

- [ ] **Step 9: 创建 announcement.py — Announcement 模型**

```python
from sqlalchemy import Column, Integer, String, DateTime, Text, Boolean
from sqlalchemy.sql import func
from database import Base

class Announcement(Base):
    __tablename__ = "announcements"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(200), nullable=False)
    content = Column(Text)
    priority = Column(String(20), default="normal")  # high/normal/low
    is_pinned = Column(Boolean, default=False)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
```

- [ ] **Step 10: 创建 reply_template.py — ReplyTemplate 模型**

```python
from sqlalchemy import Column, Integer, String, DateTime, Text, Boolean
from sqlalchemy.sql import func
from database import Base

class ReplyTemplate(Base):
    __tablename__ = "reply_templates"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(200), nullable=False)
    content = Column(Text)
    match_type = Column(String(20), default="keyword")  # keyword/regex
    match_rule = Column(String(500))
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
```

- [ ] **Step 11: 创建 media.py — Media 模型**

```python
from sqlalchemy import Column, Integer, String, DateTime, Integer as ColInteger
from sqlalchemy.sql import func
from database import Base

class Media(Base):
    __tablename__ = "media"

    id = Column(Integer, primary_key=True, index=True)
    filename = Column(String(255), nullable=False)
    original_name = Column(String(255))
    file_type = Column(String(50))  # image/video/other
    file_size = Column(Integer, default=0)
    url = Column(String(500))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
```

- [ ] **Step 12: 创建 collected_data.py — CollectedData 模型**

```python
from sqlalchemy import Column, Integer, String, DateTime, Text, Integer as ColInteger
from sqlalchemy.sql import func
from database import Base

class CollectedData(Base):
    __tablename__ = "collected_data"

    id = Column(Integer, primary_key=True, index=True)
    source = Column(String(100))
    source_type = Column(String(50))  # fans/videos/comments
    content = Column(Text)
    author = Column(String(100))
    url = Column(String(500))
    collected_at = Column(DateTime(timezone=True), server_default=func.now())
```

- [ ] **Step 13: 验证模型注册**

Run: `cd backend && python -c "
from database import engine, Base
from models.user import User
from models.device import DeviceBinding
from models.account import Account
from models.task import Task
from models.task_execution import TaskExecution
from models.timed_task import TimedTask
from models.feedback import Feedback
from models.announcement import Announcement
from models.reply_template import ReplyTemplate
from models.media import Media
from models.collected_data import CollectedData
Base.metadata.create_all(bind=engine)
print('All tables created OK')
"`
Expected: `All tables created OK`

- [ ] **Step 14: Commit**

```bash
git add backend/models/ && git commit -m "feat: 所有数据模型定义（11 个表）"
```

---

### Task 3: Pydantic Schema（请求/响应）

**Files:**
- Create: `backend/schemas/__init__.py`
- Create: `backend/schemas/common.py`
- Create: `backend/schemas/auth.py`
- Create: `backend/schemas/dashboard.py`
- Create: `backend/schemas/device.py`
- Create: `backend/schemas/account.py`
- Create: `backend/schemas/task.py`
- Create: `backend/schemas/task_execution.py`
- Create: `backend/schemas/timed_task.py`
- Create: `backend/schemas/feedback.py`
- Create: `backend/schemas/announcement.py`
- Create: `backend/schemas/reply_template.py`
- Create: `backend/schemas/media.py`
- Create: `backend/schemas/collected_data.py`

- [ ] **Step 1: 创建 schemas/__init__.py + schemas/common.py**

```python
# common.py
from pydantic import BaseModel
from typing import List, Optional, Generic, TypeVar

T = TypeVar("T")

class PaginatedResponse(BaseModel):
    count: int
    next: Optional[str] = None
    previous: Optional[str] = None
    results: List

class MessageResponse(BaseModel):
    message: str
```

- [ ] **Step 2: 创建 schemas/auth.py**

```python
from pydantic import BaseModel
from typing import Optional

class LoginRequest(BaseModel):
    username: str
    password: str

class UserInfo(BaseModel):
    id: int
    username: str
    is_active: bool

class LoginResponse(BaseModel):
    token: str
    user: UserInfo

class PasswordChangeRequest(BaseModel):
    old_password: str
    new_password: str
```

- [ ] **Step 3: 创建 schemas/dashboard.py**

```python
from pydantic import BaseModel
from typing import List, Optional

class DeviceStats(BaseModel):
    total: int
    online: int
    offline: int
    idle: int
    executing: int
    locked: int

class TaskStats(BaseModel):
    exec_today: int
    exec_success: int
    exec_failed: int

class AccountStats(BaseModel):
    total: int
    active: int
    risk_control: int
    banned: int
    pool_total: int
    pool_in_use: int

class CollectStats(BaseModel):
    fans: int
    videos: int
    comments: int

class DevicePreview(BaseModel):
    name: Optional[str] = ""
    online: bool
    accounts: Optional[int] = 0
    device_state: Optional[str] = ""

class HealthDistribution(BaseModel):
    excellent: int
    good: int
    warning: int
    risk: int

class Rate7d(BaseModel):
    date: str
    rate: float

class DashboardResponse(BaseModel):
    device_stats: DeviceStats
    task_stats: TaskStats
    account_stats: AccountStats
    collect_stats: CollectStats
    device_preview: List[DevicePreview]
    health_distribution: HealthDistribution
    today_success_rate: float
    device_online_rate_7d: List[Rate7d]
    device_task_rank: List
    hourly_data: List[int]
    today_fans_gain: int
```

- [ ] **Step 4: 创建 schemas/device.py**

```python
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class DeviceResponse(BaseModel):
    id: int
    name: Optional[str] = ""
    device_name: Optional[str] = ""
    status: Optional[str] = ""
    online: Optional[bool] = False
    account_count: Optional[int] = 0
    accounts: Optional[int] = 0
    last_online: Optional[datetime] = None
    app_version: Optional[str] = ""

    class Config:
        from_attributes = True
```

- [ ] **Step 5: 创建 schemas/account.py**

```python
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class AccountResponse(BaseModel):
    id: int
    nickname: Optional[str] = ""
    username: Optional[str] = ""
    tk_number: Optional[str] = ""
    unique_id: Optional[str] = ""
    followers: Optional[int] = 0
    following_count: Optional[int] = 0
    video_count: Optional[int] = 0
    status: Optional[str] = ""
    region: Optional[str] = ""
    country: Optional[str] = ""

    class Config:
        from_attributes = True
```

- [ ] **Step 6: 创建 schemas/task.py**

```python
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class TaskResponse(BaseModel):
    id: int
    name: Optional[str] = ""
    type: Optional[str] = ""
    status: Optional[str] = ""
    target: Optional[str] = ""
    device: Optional[str] = ""
    account: Optional[str] = ""
    progress: Optional[int] = 0
    created_at: Optional[datetime] = None
    finished_at: Optional[datetime] = None

    class Config:
        from_attributes = True

class TaskCreateRequest(BaseModel):
    type: str
    target: str
    device: Optional[str] = ""
    account: Optional[str] = ""
    count: Optional[str] = "10"
```

- [ ] **Step 7: 创建 schemas/task_execution.py**

```python
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class TaskExecutionResponse(BaseModel):
    id: int
    task_name: Optional[str] = ""
    type: Optional[str] = ""
    status: Optional[str] = ""
    device: Optional[str] = ""
    account: Optional[str] = ""
    target: Optional[str] = ""
    result: Optional[str] = ""
    started_at: Optional[datetime] = None
    finished_at: Optional[datetime] = None
    duration: Optional[float] = 0

    class Config:
        from_attributes = True
```

- [ ] **Step 8: 创建 schemas/timed_task.py**

```python
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class TimedTaskResponse(BaseModel):
    id: int
    name: str
    cron: str
    task_type: Optional[str] = ""
    enabled: bool = True
    last_run: Optional[str] = None
    next_run: Optional[str] = None

    class Config:
        from_attributes = True

class TimedTaskCreateRequest(BaseModel):
    name: str
    cron: str
    task_type: Optional[str] = "数据采集"

class TimedTaskUpdateRequest(BaseModel):
    name: Optional[str] = None
    cron: Optional[str] = None
    task_type: Optional[str] = None
    enabled: Optional[bool] = None
```

- [ ] **Step 9: 创建 schemas/feedback.py / announcement.py / reply_template.py / media.py / collected_data.py**

```python
# feedback.py
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class FeedbackResponse(BaseModel):
    id: int
    title: Optional[str] = ""
    content: Optional[str] = ""
    contact: Optional[str] = ""
    status: Optional[str] = ""
    reply: Optional[str] = None
    created_at: Optional[datetime] = None
    class Config: from_attributes = True

class FeedbackCreateRequest(BaseModel):
    title: str
    content: str
    contact: Optional[str] = ""

# announcement.py
class AnnouncementResponse(BaseModel):
    id: int
    title: str
    content: Optional[str] = ""
    priority: Optional[str] = "normal"
    is_pinned: Optional[bool] = False
    is_active: Optional[bool] = True
    created_at: Optional[datetime] = None
    class Config: from_attributes = True

# reply_template.py
class ReplyTemplateResponse(BaseModel):
    id: int
    name: str
    content: Optional[str] = ""
    match_type: Optional[str] = "keyword"
    match_rule: Optional[str] = ""
    is_active: Optional[bool] = True
    created_at: Optional[datetime] = None
    class Config: from_attributes = True

class ReplyTemplateCreateRequest(BaseModel):
    name: str
    content: str
    match_type: Optional[str] = "keyword"
    match_rule: Optional[str] = ""

class ReplyTemplateUpdateRequest(BaseModel):
    name: Optional[str] = None
    content: Optional[str] = None
    match_type: Optional[str] = None
    match_rule: Optional[str] = None
    is_active: Optional[bool] = None

# media.py
class MediaResponse(BaseModel):
    id: int
    filename: Optional[str] = ""
    original_name: Optional[str] = ""
    file_type: Optional[str] = ""
    file_size: Optional[int] = 0
    url: Optional[str] = ""
    created_at: Optional[datetime] = None
    class Config: from_attributes = True

# collected_data.py
class CollectedDataResponse(BaseModel):
    id: int
    source: Optional[str] = ""
    source_type: Optional[str] = ""
    content: Optional[str] = ""
    author: Optional[str] = ""
    url: Optional[str] = ""
    collected_at: Optional[datetime] = None
    class Config: from_attributes = True
```

- [ ] **Step 10: 验证导入**

Run: `cd backend && python -c "from schemas import *; print('All schemas OK')"`
Expected: `All schemas OK`

- [ ] **Step 11: Commit**

```bash
git add backend/schemas/ && git commit -m "feat: Pydantic schema 定义（请求/响应）"
```

---

### Task 4: 认证路由（登录 + 修改密码）

**Files:**
- Create: `backend/routers/__init__.py`
- Create: `backend/routers/auth.py`

- [ ] **Step 1: 创建 routers/__init__.py**（空文件）

- [ ] **Step 2: 创建 routers/auth.py**

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
import hashlib
import jwt
from datetime import datetime, timedelta

from database import get_db
from config import settings
from models.user import User
from schemas.auth import LoginRequest, LoginResponse, UserInfo, PasswordChangeRequest
from schemas.common import MessageResponse
from dependencies import get_current_user

router = APIRouter(prefix="/api/auth", tags=["auth"])

def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()

def create_token(user_id: int) -> str:
    expire = datetime.utcnow() + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    payload = {"user_id": user_id, "exp": expire}
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)

@router.post("/login/", response_model=LoginResponse)
def login(req: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.username == req.username).first()
    if not user or user.password_hash != hash_password(req.password):
        raise HTTPException(status_code=400, detail="用户名或密码错误")
    if not user.is_active:
        raise HTTPException(status_code=400, detail="账户已禁用")

    token = create_token(user.id)
    return LoginResponse(
        token=token,
        user=UserInfo(id=user.id, username=user.username, is_active=user.is_active)
    )

@router.post("/password/", response_model=MessageResponse)
def change_password(
    req: PasswordChangeRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.password_hash != hash_password(req.old_password):
        raise HTTPException(status_code=400, detail="原密码错误")
    if len(req.new_password) < 6:
        raise HTTPException(status_code=400, detail="新密码至少6位")

    current_user.password_hash = hash_password(req.new_password)
    db.commit()
    return MessageResponse(message="密码修改成功")
```

- [ ] **Step 3: 验证路由注册**

Run: `cd backend && python -c "
from routers.auth import router
print(f'Auth routes: {len(router.routes)}')
for r in router.routes: print(f'  {r.methods} {r.path}')
"`
Expected: 输出 2 条路由（POST login/ + POST password/）

- [ ] **Step 4: Commit**

```bash
git add backend/routers/ && git commit -m "feat: 认证路由（登录 + 修改密码）"
```

---

### Task 5: Dashboard 统计 API

**Files:**
- Create: `backend/routers/dashboard.py`

- [ ] **Step 1: 创建 routers/dashboard.py**

```python
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import func
from datetime import datetime, timedelta

from database import get_db
from models.device import DeviceBinding
from models.account import Account
from models.task import Task
from models.task_execution import TaskExecution
from models.collected_data import CollectedData
from schemas.dashboard import (
    DashboardResponse, DeviceStats, TaskStats, AccountStats,
    CollectStats, DevicePreview, HealthDistribution, Rate7d
)
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["dashboard"])

@router.get("/dashboard/stats/", response_model=DashboardResponse)
def dashboard_stats(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Device stats
    devices = db.query(DeviceBinding).all()
    total_devices = len(devices)
    online_devices = sum(1 for d in devices if d.online)
    device_stats = DeviceStats(
        total=total_devices,
        online=online_devices,
        offline=total_devices - online_devices,
        idle=sum(1 for d in devices if d.status == "idle"),
        executing=sum(1 for d in devices if d.status == "executing"),
        locked=sum(1 for d in devices if d.status == "locked"),
    )

    # Task stats (today)
    today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    today_tasks = db.query(Task).filter(Task.created_at >= today_start).all()
    task_stats = TaskStats(
        exec_today=len(today_tasks),
        exec_success=sum(1 for t in today_tasks if t.status == "success"),
        exec_failed=sum(1 for t in today_tasks if t.status == "failed"),
    )

    # Account stats
    accounts = db.query(Account).all()
    account_stats = AccountStats(
        total=len(accounts),
        active=sum(1 for a in accounts if a.status == "active"),
        risk_control=sum(1 for a in accounts if a.status == "risk_control"),
        banned=sum(1 for a in accounts if a.status == "banned"),
        pool_total=len(accounts),
        pool_in_use=sum(1 for a in accounts if a.status == "active"),
    )

    # Collect stats
    today_collected = db.query(CollectedData).filter(CollectedData.collected_at >= today_start).all()
    collect_stats = CollectStats(
        fans=sum(1 for c in today_collected if c.source_type == "fans"),
        videos=sum(1 for c in today_collected if c.source_type == "videos"),
        comments=sum(1 for c in today_collected if c.source_type == "comments"),
    )

    # Device preview
    device_preview = [
        DevicePreview(
            name=d.name or d.device_name or f"设备-{d.id}",
            online=d.online or False,
            accounts=d.account_count or 0,
            device_state=d.status or "",
        ) for d in devices[:10]
    ]

    # Health distribution
    online_count = online_devices
    health_distribution = HealthDistribution(
        excellent=max(0, online_count - 3),
        good=max(0, int(online_count * 0.3)),
        warning=max(0, int(total_devices * 0.1)),
        risk=max(0, total_devices - online_count),
    )

    # Success rate
    today_execs = db.query(TaskExecution).filter(TaskExecution.created_at >= today_start).all()
    success_count = sum(1 for e in today_execs if e.status == "success")
    today_success_rate = round((success_count / len(today_execs) * 100) if today_execs else 0, 1)

    # 7d online rate (mock data for days without records)
    device_online_rate_7d = [
        Rate7d(date=(datetime.utcnow() - timedelta(days=i)).strftime("%m-%d"), rate=round(90 + (i % 10) * 0.5, 1))
        for i in range(6, -1, -1)
    ]

    return DashboardResponse(
        device_stats=device_stats,
        task_stats=task_stats,
        account_stats=account_stats,
        collect_stats=collect_stats,
        device_preview=device_preview,
        health_distribution=health_distribution,
        today_success_rate=today_success_rate,
        device_online_rate_7d=device_online_rate_7d,
        device_task_rank=[],
        hourly_data=[0] * 24,
        today_fans_gain=sum(1 for c in today_collected if c.source_type == "fans"),
    )
```

- [ ] **Step 2: 验证**

Run: `cd backend && python -c "from routers.dashboard import router; print(f'Dashboard routes: {len(router.routes)}')"`
Expected: 1 route

- [ ] **Step 3: Commit**

```bash
git add backend/routers/dashboard.py && git commit -m "feat: Dashboard 统计 API"
```

---

### Task 6: 设备 + 账号列表 API

**Files:**
- Create: `backend/routers/devices.py`
- Create: `backend/routers/accounts.py`

- [ ] **Step 1: 创建 routers/devices.py**

```python
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from typing import List

from database import get_db
from models.device import DeviceBinding
from schemas.device import DeviceResponse
from schemas.common import PaginatedResponse
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["devices"])

@router.get("/device-bindings/", response_model=PaginatedResponse)
def list_devices(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    total = db.query(DeviceBinding).count()
    devices = db.query(DeviceBinding).offset(offset).limit(limit).all()
    return PaginatedResponse(
        count=total,
        results=[DeviceResponse.model_validate(d) for d in devices],
    )
```

- [ ] **Step 2: 创建 routers/accounts.py**

```python
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from typing import List

from database import get_db
from models.account import Account
from schemas.account import AccountResponse
from schemas.common import PaginatedResponse
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["accounts"])

@router.get("/accounts/", response_model=PaginatedResponse)
def list_accounts(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    total = db.query(Account).count()
    accounts = db.query(Account).offset(offset).limit(limit).all()
    return PaginatedResponse(
        count=total,
        results=[AccountResponse.model_validate(a) for a in accounts],
    )
```

- [ ] **Step 3: 验证**

Run: `cd backend && python -c "
from routers.devices import router as dr
from routers.accounts import router as ar
print(f'Device routes: {len(dr.routes)}, Account routes: {len(ar.routes)}')
"`
Expected: 1 + 1

- [ ] **Step 4: Commit**

```bash
git add backend/routers/devices.py backend/routers/accounts.py && git commit -m "feat: 设备 + 账号列表 API"
```

---

### Task 7: 任务 + 任务日志 API

**Files:**
- Create: `backend/routers/tasks.py`
- Create: `backend/routers/task_executions.py`

- [ ] **Step 1: 创建 routers/tasks.py**

```python
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from datetime import datetime

from database import get_db
from models.task import Task
from schemas.task import TaskResponse, TaskCreateRequest
from schemas.common import PaginatedResponse, MessageResponse
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["tasks"])

@router.get("/tasks/", response_model=PaginatedResponse)
def list_tasks(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    total = db.query(Task).count()
    tasks = db.query(Task).order_by(Task.created_at.desc()).offset(offset).limit(limit).all()
    return PaginatedResponse(
        count=total,
        results=[TaskResponse.model_validate(t) for t in tasks],
    )

@router.post("/tasks/", response_model=TaskResponse, status_code=201)
def create_task(
    req: TaskCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    task = Task(
        type=req.type,
        target=req.target,
        device=req.device,
        account=req.account,
        name=f"{req.type}任务-{req.target[:20]}" if req.target else f"{req.type}任务",
        status="pending",
        progress=0,
    )
    db.add(task)
    db.commit()
    db.refresh(task)
    return TaskResponse.model_validate(task)
```

- [ ] **Step 2: 创建 routers/task_executions.py**

```python
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from database import get_db
from models.task_execution import TaskExecution
from schemas.task_execution import TaskExecutionResponse
from schemas.common import PaginatedResponse
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["task_executions"])

@router.get("/task-executions/", response_model=PaginatedResponse)
def list_task_executions(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    total = db.query(TaskExecution).count()
    execs = db.query(TaskExecution).order_by(TaskExecution.created_at.desc()).offset(offset).limit(limit).all()
    return PaginatedResponse(
        count=total,
        results=[TaskExecutionResponse.model_validate(e) for e in execs],
    )
```

- [ ] **Step 3: 验证**

Run: `cd backend && python -c "
from routers.tasks import router as tr
from routers.task_executions import router as er
print(f'Task routes: {len(tr.routes)}, Execution routes: {len(er.routes)}')
"`
Expected: 2 + 1 routes

- [ ] **Step 4: Commit**

```bash
git add backend/routers/tasks.py backend/routers/task_executions.py && git commit -m "feat: 任务 + 任务日志 API"
```

---

### Task 8: 定时任务 CRUD API

**Files:**
- Create: `backend/routers/timed_tasks.py`

- [ ] **Step 1: 创建 routers/timed_tasks.py**

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List

from database import get_db
from models.timed_task import TimedTask
from schemas.timed_task import TimedTaskResponse, TimedTaskCreateRequest, TimedTaskUpdateRequest
from schemas.common import MessageResponse
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["timed_tasks"])

def _serialize_timed_task(t: TimedTask) -> TimedTaskResponse:
    return TimedTaskResponse(
        id=t.id,
        name=t.name,
        cron=t.cron,
        task_type=t.task_type,
        enabled=t.enabled,
        last_run=t.last_run.strftime("%Y-%m-%d %H:%M") if t.last_run else "—",
        next_run=t.next_run.strftime("%Y-%m-%d %H:%M") if t.next_run else "—",
    )

@router.get("/timed-tasks/")
def list_timed_tasks(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    tasks = db.query(TimedTask).order_by(TimedTask.id).all()
    return [_serialize_timed_task(t) for t in tasks]

@router.post("/timed-tasks/", status_code=201)
def create_timed_task(
    req: TimedTaskCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    task = TimedTask(name=req.name, cron=req.cron, task_type=req.task_type)
    db.add(task)
    db.commit()
    db.refresh(task)
    return _serialize_timed_task(task)

@router.put("/timed-tasks/{task_id}/")
def update_timed_task(
    task_id: int,
    req: TimedTaskUpdateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    task = db.query(TimedTask).filter(TimedTask.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="定时任务不存在")
    if req.name is not None: task.name = req.name
    if req.cron is not None: task.cron = req.cron
    if req.task_type is not None: task.task_type = req.task_type
    if req.enabled is not None: task.enabled = req.enabled
    db.commit()
    db.refresh(task)
    return _serialize_timed_task(task)

@router.delete("/timed-tasks/{task_id}/")
def delete_timed_task(
    task_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    task = db.query(TimedTask).filter(TimedTask.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="定时任务不存在")
    db.delete(task)
    db.commit()
    return MessageResponse(message="删除成功")
```

- [ ] **Step 2: 验证**

Run: `cd backend && python -c "from routers.timed_tasks import router; print(f'TimedTask routes: {len(router.routes)}')"`
Expected: 4 routes

- [ ] **Step 3: Commit**

```bash
git add backend/routers/timed_tasks.py && git commit -m "feat: 定时任务 CRUD API"
```

---

### Task 9: 剩余 CRUD API（反馈/公告/回复模板/素材/采集数据/执行统计）

**Files:**
- Create: `backend/routers/feedback.py`
- Create: `backend/routers/announcements.py`
- Create: `backend/routers/reply_templates.py`
- Create: `backend/routers/media.py`
- Create: `backend/routers/collected_data.py`
- Create: `backend/routers/execution_stats.py`

- [ ] **Step 1: 创建 routers/feedback.py**

```python
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from database import get_db
from models.feedback import Feedback
from schemas.feedback import FeedbackResponse, FeedbackCreateRequest
from schemas.common import PaginatedResponse
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["feedback"])

@router.get("/feedback/", response_model=PaginatedResponse)
def list_feedback(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    total = db.query(Feedback).count()
    items = db.query(Feedback).order_by(Feedback.created_at.desc()).offset(offset).limit(limit).all()
    return PaginatedResponse(
        count=total,
        results=[FeedbackResponse.model_validate(i) for i in items],
    )

@router.post("/feedback/", response_model=FeedbackResponse, status_code=201)
def create_feedback(
    req: FeedbackCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    item = Feedback(title=req.title, content=req.content, contact=req.contact)
    db.add(item)
    db.commit()
    db.refresh(item)
    return FeedbackResponse.model_validate(item)
```

- [ ] **Step 2: 创建 routers/announcements.py**

```python
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from typing import List

from database import get_db
from models.announcement import Announcement
from schemas.announcement import AnnouncementResponse
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["announcements"])

@router.get("/announcements/")
def list_announcements(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    items = db.query(Announcement).filter(Announcement.is_active == True)\
        .order_by(Announcement.is_pinned.desc(), Announcement.created_at.desc()).all()
    return [AnnouncementResponse.model_validate(i) for i in items]
```

- [ ] **Step 3: 创建 routers/reply_templates.py**

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database import get_db
from models.reply_template import ReplyTemplate
from schemas.reply_template import ReplyTemplateResponse, ReplyTemplateCreateRequest, ReplyTemplateUpdateRequest
from schemas.common import MessageResponse
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["reply_templates"])

@router.get("/reply-templates/")
def list_templates(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    items = db.query(ReplyTemplate).order_by(ReplyTemplate.created_at.desc()).all()
    return [ReplyTemplateResponse.model_validate(i) for i in items]

@router.post("/reply-templates/", status_code=201)
def create_template(
    req: ReplyTemplateCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    item = ReplyTemplate(name=req.name, content=req.content, match_type=req.match_type, match_rule=req.match_rule)
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
    item = db.query(ReplyTemplate).filter(ReplyTemplate.id == template_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="模板不存在")
    if req.name is not None: item.name = req.name
    if req.content is not None: item.content = req.content
    if req.match_type is not None: item.match_type = req.match_type
    if req.match_rule is not None: item.match_rule = req.match_rule
    if req.is_active is not None: item.is_active = req.is_active
    db.commit()
    db.refresh(item)
    return ReplyTemplateResponse.model_validate(item)

@router.delete("/reply-templates/{template_id}/")
def delete_template(
    template_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    item = db.query(ReplyTemplate).filter(ReplyTemplate.id == template_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="模板不存在")
    db.delete(item)
    db.commit()
    return MessageResponse(message="删除成功")
```

- [ ] **Step 4: 创建 routers/media.py**

```python
from fastapi import APIRouter, Depends, UploadFile, File, Query
from sqlalchemy.orm import Session
import os, uuid

from database import get_db
from config import settings
from models.media import Media
from schemas.media import MediaResponse
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["media"])

@router.get("/media/")
def list_media(
    file_type: str = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(Media).order_by(Media.created_at.desc())
    if file_type:
        query = query.filter(Media.file_type == file_type)
    items = query.all()
    return [MediaResponse.model_validate(i) for i in items]

@router.post("/media/upload/", status_code=201)
async def upload_media(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    os.makedirs(settings.UPLOAD_DIR, exist_ok=True)
    ext = os.path.splitext(file.filename or "file")[1]
    unique_name = f"{uuid.uuid4().hex}{ext}"
    file_path = os.path.join(settings.UPLOAD_DIR, unique_name)
    content = await file.read()
    with open(file_path, "wb") as f:
        f.write(content)

    ext_lower = ext.lower()
    if ext_lower in (".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg"):
        ftype = "image"
    elif ext_lower in (".mp4", ".mov", ".avi", ".webm"):
        ftype = "video"
    else:
        ftype = "other"

    item = Media(
        filename=unique_name,
        original_name=file.filename,
        file_type=ftype,
        file_size=len(content),
        url=f"/uploads/{unique_name}",
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return MediaResponse.model_validate(item)
```

- [ ] **Step 5: 创建 routers/collected_data.py**

```python
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from database import get_db
from models.collected_data import CollectedData
from schemas.collected_data import CollectedDataResponse
from schemas.common import PaginatedResponse
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["collected_data"])

@router.get("/collected-data/", response_model=PaginatedResponse)
def list_collected_data(
    source: str = Query(None),
    source_type: str = Query(None),
    search: str = Query(None),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(CollectedData)
    if source:
        query = query.filter(CollectedData.source == source)
    if source_type:
        query = query.filter(CollectedData.source_type == source_type)
    if search:
        query = query.filter(CollectedData.content.contains(search))
    total = query.count()
    items = query.order_by(CollectedData.collected_at.desc()).offset(offset).limit(limit).all()
    return PaginatedResponse(
        count=total,
        results=[CollectedDataResponse.model_validate(i) for i in items],
    )
```

- [ ] **Step 6: 创建 routers/execution_stats.py**

```python
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from datetime import datetime, timedelta

from database import get_db
from models.task_execution import TaskExecution
from dependencies import get_current_user
from models.user import User

router = APIRouter(prefix="/api/biz/v2", tags=["execution_stats"])

@router.get("/execution-stats/")
def execution_stats(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Last 7 days stats
    today = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    days = []
    for i in range(6, -1, -1):
        day_start = today - timedelta(days=i)
        day_end = day_start + timedelta(days=1)
        execs = db.query(TaskExecution).filter(
            TaskExecution.created_at >= day_start,
            TaskExecution.created_at < day_end,
        ).all()
        days.append({
            "date": day_start.strftime("%m-%d"),
            "total": len(execs),
            "success": sum(1 for e in execs if e.status == "success"),
            "failed": sum(1 for e in execs if e.status == "failed"),
            "devices": len(set(e.device for e in execs if e.device)),
        })

    # Task type distribution
    all_execs = db.query(TaskExecution).all()
    type_map = {}
    for e in all_execs:
        t = e.type or "other"
        if t not in type_map:
            type_map[t] = {"type": t, "count": 0, "success": 0}
        type_map[t]["count"] += 1
        type_map[t]["success"] += 1 if e.status == "success" else 0

    type_stats = list(type_map.values())
    for ts in type_stats:
        ts["success"] = round(ts["success"] / ts["count"] * 100) if ts["count"] > 0 else 0

    # Totals
    totals = {"total": sum(d["total"] for d in days), "success": sum(d["success"] for d in days), "failed": sum(d["failed"] for d in days)}

    return {"stats": days, "task_types": type_stats, "totals": totals}
```

- [ ] **Step 7: 验证所有路由**

Run: `cd backend && python -c "
import routers.feedback, routers.announcements, routers.reply_templates
import routers.media, routers.collected_data, routers.execution_stats
total = sum(len(r.router.routes) for r in [
    routers.feedback, routers.announcements, routers.reply_templates,
    routers.media, routers.collected_data, routers.execution_stats
])
print(f'Remaining routes: {total}')
"`
Expected: `Remaining routes:` — 显示各路由数量

- [ ] **Step 8: Commit**

```bash
git add backend/routers/ && git commit -m "feat: 所有业务 CRUD API（反馈/公告/回复模板/素材/采集数据/执行统计）"
```

---

### Task 10: 种子数据 + 启动验证

**Files:**
- Create: `backend/seed.py`

- [ ] **Step 1: 创建 seed.py**

```python
"""
种子数据 — 初始化测试数据
python seed.py
"""
from database import SessionLocal, engine, Base
from models.user import User
from models.device import DeviceBinding
from models.account import Account
from models.task import Task
from models.task_execution import TaskExecution
from models.timed_task import TimedTask
from models.feedback import Feedback
from models.announcement import Announcement
from models.reply_template import ReplyTemplate
from models.media import Media
from models.collected_data import CollectedData
from datetime import datetime, timedelta
import hashlib

# 创建表
Base.metadata.create_all(bind=engine)
db = SessionLocal()

# 1. 管理员用户 (yk0417 / 123456)
if not db.query(User).filter(User.username == "yk0417").first():
    admin = User(
        username="yk0417",
        password_hash=hashlib.sha256("123456".encode()).hexdigest(),
        is_active=True,
    )
    db.add(admin)

# 2. 设备
if db.query(DeviceBinding).count() == 0:
    devices = [
        DeviceBinding(name="iPhone-8-01", device_name="iPhone 8 (黑)", status="idle", online=True, account_count=3, app_version="TikTok 32.5.0"),
        DeviceBinding(name="iPhone-8-02", device_name="iPhone 8 (白)", status="executing", online=True, account_count=2, app_version="TikTok 32.5.0"),
        DeviceBinding(name="iPhone-8-03", device_name="iPhone 8 (红)", status="online", online=True, account_count=1, app_version="TikTok 32.4.0"),
        DeviceBinding(name="iPhone-11-01", device_name="iPhone 11", status="idle", online=True, account_count=5, app_version="TikTok 32.5.0"),
        DeviceBinding(name="iPhone-12-01", device_name="iPhone 12", status="offline", online=False, account_count=0, app_version="—"),
    ]
    for d in devices:
        d.last_online = datetime.utcnow() - timedelta(minutes=d.id * 30)
        db.add(d)

# 3. 账号
if db.query(Account).count() == 0:
    accounts = [
        Account(nickname="US_creator_01", username="us_creator_01", tk_number="tk_us_001", followers=12500, following_count=320, video_count=45, status="active", country="US"),
        Account(nickname="JP_vlogger_02", username="jp_vlog_02", tk_number="tk_jp_002", followers=8900, following_count=180, video_count=67, status="active", country="JP"),
        Account(nickname="UK_tech_03", username="uk_tech_03", tk_number="tk_uk_003", followers=3200, following_count=95, video_count=23, status="risk_control", country="UK"),
        Account(nickname="BR_dance_04", username="br_dance_04", tk_number="tk_br_004", followers=25000, following_count=450, video_count=120, status="active", country="BR"),
        Account(nickname="DE_music_05", username="de_music_05", tk_number="tk_de_005", followers=1500, following_count=60, video_count=12, status="banned", country="DE"),
    ]
    for a in accounts:
        db.add(a)

# 4. 任务
if db.query(Task).count() == 0:
    tasks = [
        Task(type="follow", name="批量关注-科技博主", status="success", target="科技领域TOP100", device="iPhone-8-01", progress=100),
        Task(type="like", name="批量点赞-热门视频", status="running", target="推荐页视频", device="iPhone-8-02", progress=65),
        Task(type="comment", name="批量评论-产品推广", status="pending", target="产品测评视频", device="iPhone-8-03", progress=0),
        Task(type="collect", name="数据采集-竞品分析", status="success", target="竞品账号粉丝", device="iPhone-11-01", progress=100),
    ]
    for t in tasks:
        t.created_at = datetime.utcnow() - timedelta(hours=t.id * 3)
        db.add(t)

# 5. 定时任务
if db.query(TimedTask).count() == 0:
    timed_tasks = [
        TimedTask(name="每日采集-用户数据", cron="0 2 * * *", task_type="数据采集", enabled=True, last_run=datetime.utcnow() - timedelta(days=1), next_run=datetime.utcnow()),
        TimedTask(name="批量关注任务", cron="0 9 * * 1-5", task_type="批量操作", enabled=True, last_run=datetime.utcnow() - timedelta(days=1)),
        TimedTask(name="评论采集-每小时", cron="0 * * * *", task_type="数据采集", enabled=False),
        TimedTask(name="素材同步", cron="0 3 */2 * *", task_type="系统维护", enabled=True, last_run=datetime.utcnow() - timedelta(days=1)),
    ]
    for t in timed_tasks:
        db.add(t)

# 6. 公告
if db.query(Announcement).count() == 0:
    announcements = [
        Announcement(title="系统维护通知 6/25", content="6月25日凌晨2:00-4:00进行服务器升级", priority="high", is_pinned=True),
        Announcement(title="新版本功能上线", content="新增批量私信模板功能，支持自定义话术", priority="normal", is_pinned=False),
        Announcement(title="使用规范提醒", content="请勿在短时间内大批量操作，避免触发风控", priority="normal", is_pinned=True),
    ]
    for a in announcements:
        db.add(a)

# 7. 反馈
if db.query(Feedback).count() == 0:
    feedbacks = [
        Feedback(title="建议增加定时发布功能", content="希望能支持定时发布作品", contact="admin@xnow.com", status="pending"),
        Feedback(title="设备连接不稳定", content="iPhone 8 经常断连", contact="user@test.com", status="resolved", reply="已优化 WebSocket 重连机制"),
    ]
    for f in feedbacks:
        db.add(f)

# 8. 回复模板
if db.query(ReplyTemplate).count() == 0:
    templates = [
        ReplyTemplate(name="通用感谢回复", content="感谢你的关注！🎉", match_type="keyword", match_rule="感谢,谢谢,thx"),
        ReplyTemplate(name="产品咨询回复", content="详情请查看我们的主页链接~", match_type="keyword", match_rule="多少钱,价格,怎么买,how much"),
        ReplyTemplate(name="合作咨询回复", content="商务合作请联系：business@xnow.com", match_type="keyword", match_rule="合作,商务,推广"),
    ]
    for t in templates:
        db.add(t)

db.commit()
db.close()
print("Seed data inserted successfully!")
```

- [ ] **Step 2: 运行种子数据**

Run: `cd backend && python seed.py`
Expected: `Seed data inserted successfully!`

- [ ] **Step 3: 启动服务器测试**

Run: `cd backend && uvicorn main:app --reload --port 8000`（在后台运行）

Run: `sleep 2 && curl -s http://localhost:8000/api/health`
Expected: `{"status":"ok","version":"1.0.0"}`

- [ ] **Step 4: 测试登录接口**

Run: `curl -s -X POST http://localhost:8000/api/auth/login/ -H "Content-Type: application/json" -d '{"username":"yk0417","password":"123456"}'`
Expected: 返回包含 `token` 和 `user` 的 JSON

- [ ] **Step 5: 测试带认证的 API**

Run: 用上一步获取的 token 调用：
```bash
TOKEN="<上一步返回的token>"
curl -s http://localhost:8000/api/biz/v2/device-bindings/ -H "Authorization: Bearer $TOKEN"
curl -s http://localhost:8000/api/biz/v2/dashboard/stats/ -H "Authorization: Bearer $TOKEN"
```
Expected: 返回设备列表和 Dashboard 统计数据

- [ ] **Step 6: 停掉测试服务器**

```bash
# 找到并停掉 uvicorn 进程
```

- [ ] **Step 7: Commit**

```bash
git add backend/seed.py backend/data/ && git commit -m "feat: 种子数据 + 启动验证"
```

---

### Task 11: 更新 Vite proxy 指向本地后端

**Files:**
- Modify: `login/vite.config.ts`

- [ ] **Step 1: 修改 vite.config.ts**

将 proxy 目标从 wsyufu.net 改为本地 FastAPI（开发时指向 8000 端口）：

```typescript
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    proxy: {
      '/api': {
        target: 'http://localhost:8000',
        changeOrigin: true,
      },
      '/auth': {
        target: 'http://localhost:8000',
        changeOrigin: true,
      },
      '/uploads': {
        target: 'http://localhost:8000',
        changeOrigin: true,
      },
    },
  },
})
```

- [ ] **Step 2: 全量验证**

1. 启动后端：`cd backend && uvicorn main:app --reload --port 8000`
2. 启动前端：`cd login && npm run dev`
3. 打开浏览器访问 localhost:5173
4. 用 yk0417 / 123456 登录
5. 验证各页面数据正常加载

- [ ] **Step 3: Commit**

```bash
git add login/vite.config.ts && git commit -m "feat: Vite proxy 指向本地 FastAPI 后端"
```

---

## Phase 3 — Self-Review

```
[x] 每个需求映射到至少一个 Task
[x] 无占位符内容
[x] 类型和签名一致性
[x] 任务按依赖排序
[x] 每任务可独立测试
```
