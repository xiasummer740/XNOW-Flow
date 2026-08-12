from sqlalchemy import create_engine, text, event
from sqlalchemy.orm import sessionmaker, DeclarativeBase

from config import settings

# 优化4: SQLite WAL模式 + busy_timeout — 降低并发读写锁冲突
engine = create_engine(
    settings.DATABASE_URL,
    connect_args={
        "check_same_thread": False,   # SQLite only
        "timeout": 10,                # busy_timeout 10s（连接级）
    }
)
# 连接建立后设置 PRAGMA（WAL 允许读写并发，减少 "database is locked"）
@event.listens_for(engine, "connect")
def _set_sqlite_pragma(dbapi_connection, connection_record):
    try:
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("PRAGMA busy_timeout=10000")
        cursor.execute("PRAGMA synchronous=NORMAL")
        cursor.close()
    except Exception:
        pass

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

class Base(DeclarativeBase):
    pass


def _migrate_tenant_columns():
    """SQLite 迁移：补齐租户隔离所需的列并回填旧数据。

    仅处理已存在的旧表（create_all 不会给已存在表加列），失败不影响启动。
    - accounts.api_id  -> 旧账号归到 admin(api_id='1')
    - users.role       -> 旧 admin 用户补 role='admin'（不覆盖已有值）
    - users.api_id     -> 旧 admin 用户补 api_id='1'
    """
    try:
        with engine.connect() as conn:
            tables = [r[0] for r in conn.execute(text(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )).fetchall()]

            # accounts.api_id：新库 create_all 已含该列，此处仅处理旧库
            if "accounts" in tables:
                cols = [r[1] for r in conn.execute(text("PRAGMA table_info(accounts)")).fetchall()]
                if "api_id" not in cols:
                    conn.execute(text("ALTER TABLE accounts ADD COLUMN api_id VARCHAR(20) DEFAULT ''"))
                conn.execute(text(
                    "UPDATE accounts SET api_id = '1' WHERE api_id IS NULL OR api_id = ''"
                ))

            # users.role / users.api_id：旧库缺失这两个列，补齐并回填 admin
            if "users" in tables:
                cols = [r[1] for r in conn.execute(text("PRAGMA table_info(users)")).fetchall()]
                if "role" not in cols:
                    conn.execute(text("ALTER TABLE users ADD COLUMN role VARCHAR(20) DEFAULT 'user'"))
                if "api_id" not in cols:
                    conn.execute(text("ALTER TABLE users ADD COLUMN api_id VARCHAR(64) DEFAULT NULL"))
                # 注意：ADD COLUMN 会把既有行填成 DEFAULT 'user'，因此必须无条件把 admin 置为 admin
                conn.execute(text(
                    "UPDATE users SET role='admin' WHERE username='admin'"
                ))
                conn.execute(text(
                    "UPDATE users SET api_id='1' WHERE username='admin' AND (api_id IS NULL OR api_id='')"
                ))

            # 商用配额：users / licenses 补配额列（NULL=按套餐默认，迁移期不覆盖存量数据）
            if "users" in tables:
                cols = [r[1] for r in conn.execute(text("PRAGMA table_info(users)")).fetchall()]
                if "device_limit" not in cols:
                    conn.execute(text("ALTER TABLE users ADD COLUMN device_limit INTEGER"))
                if "account_limit" not in cols:
                    conn.execute(text("ALTER TABLE users ADD COLUMN account_limit INTEGER"))
            if "licenses" in tables:
                cols = [r[1] for r in conn.execute(text("PRAGMA table_info(licenses)")).fetchall()]
                if "device_limit" not in cols:
                    conn.execute(text("ALTER TABLE licenses ADD COLUMN device_limit INTEGER"))
                if "account_limit" not in cols:
                    conn.execute(text("ALTER TABLE licenses ADD COLUMN account_limit INTEGER"))

            # device_bindings.device_code：绑定编号存独立列（不改name防丢指令）
            if "device_bindings" in tables:
                cols = [r[1] for r in conn.execute(text("PRAGMA table_info(device_bindings)")).fetchall()]
                if "device_code" not in cols:
                    conn.execute(text("ALTER TABLE device_bindings ADD COLUMN device_code VARCHAR(50) DEFAULT ''"))
                if "added_by" not in cols:
                    conn.execute(text("ALTER TABLE device_bindings ADD COLUMN added_by VARCHAR(100) DEFAULT '系统'"))

            # timed_tasks: 定时任务目标设备/指令列（优化2调度器用）
            if "timed_tasks" in tables:
                cols = [r[1] for r in conn.execute(text("PRAGMA table_info(timed_tasks)")).fetchall()]
                if "device_ids" not in cols:
                    conn.execute(text("ALTER TABLE timed_tasks ADD COLUMN device_ids TEXT DEFAULT '[]'"))
                if "action" not in cols:
                    conn.execute(text("ALTER TABLE timed_tasks ADD COLUMN action VARCHAR(50) DEFAULT ''"))
                if "params" not in cols:
                    conn.execute(text("ALTER TABLE timed_tasks ADD COLUMN params TEXT DEFAULT '{}'"))

            conn.commit()
    except Exception as e:
        print(f"[migration] 租户列迁移失败（可忽略）: {e}")


def _migrate_collected_data_columns():
    """SQLite 迁移：补齐采集数据表增强字段并回填旧数据。

    仅处理已存在的旧表（create_all 不会给已存在表加列），失败不影响启动。
    新增列（ALTER-safe）：gender/region/followers/aweme_id/group_name/api_id/remark/dedupe_key
    旧数据归到 admin(api_id='1')。
    """
    try:
        with engine.connect() as conn:
            tables = [r[0] for r in conn.execute(text(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )).fetchall()]

            if "collected_data" in tables:
                cols = [r[1] for r in conn.execute(text("PRAGMA table_info(collected_data)")).fetchall()]
                add_cols = {
                    "gender": "VARCHAR(20) DEFAULT ''",
                    "region": "VARCHAR(50) DEFAULT ''",
                    "followers": "INTEGER DEFAULT 0",
                    "following_count": "INTEGER DEFAULT 0",
                    "age": "INTEGER DEFAULT 0",
                    "aweme_id": "VARCHAR(100) DEFAULT ''",
                    "group_name": "VARCHAR(100) DEFAULT '未分组'",
                    "api_id": "VARCHAR(64) DEFAULT ''",
                    "remark": "TEXT DEFAULT ''",
                    "dedupe_key": "VARCHAR(200) DEFAULT ''",
                }
                for name, ddl in add_cols.items():
                    if name not in cols:
                        conn.execute(text(f"ALTER TABLE collected_data ADD COLUMN {name} {ddl}"))
                # 回填旧数据到 admin 租户
                conn.execute(text(
                    "UPDATE collected_data SET api_id = '1' WHERE api_id IS NULL OR api_id = ''"
                ))
                conn.commit()
    except Exception as e:
        print(f"[migration] 采集数据列迁移失败（可忽略）: {e}")


def _migrate_add_api_id(table):
    """SQLite 迁移：为指定表补齐 api_id 列并回填旧数据。

    仅处理已存在的旧表（create_all 不会给已存在表加列），失败不影响启动。
    旧数据归到 admin 租户（api_id='1'）。幂等可重复执行。
    """
    try:
        with engine.connect() as conn:
            tables = [r[0] for r in conn.execute(text(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )).fetchall()]
            if table not in tables:
                return
            cols = [r[1] for r in conn.execute(text(f"PRAGMA table_info({table})")).fetchall()]
            if "api_id" not in cols:
                conn.execute(text(
                    f"ALTER TABLE {table} ADD COLUMN api_id VARCHAR(20) DEFAULT ''"
                ))
            conn.execute(text(
                f"UPDATE {table} SET api_id = '1' WHERE api_id IS NULL OR api_id = ''"
            ))
            conn.commit()
    except Exception as e:
        print(f"[migration] {table}.api_id 迁移失败（可忽略）: {e}")


def _migrate_video_posts():
    """SQLite 迁移：确保 video_posts 表存在。

    新库由 create_all 自动建表，此迁移仅处理旧库（create_all 不会给已存在的库补表）。
    使用与现有迁移一致的原始 SQL，幂等可重复执行。
    """
    try:
        with engine.connect() as conn:
            conn.execute(text("""
                CREATE TABLE IF NOT EXISTS video_posts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    device_id VARCHAR(100),
                    video_url TEXT DEFAULT '',
                    title TEXT DEFAULT '',
                    category VARCHAR(30) DEFAULT 'auto_post',
                    status VARCHAR(20) DEFAULT 'pending',
                    scheduled_at DATETIME,
                    api_id VARCHAR(64) DEFAULT '',
                    result TEXT DEFAULT '',
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
                )
            """))
            conn.commit()
    except Exception as e:
        print(f"[migration] video_posts 表迁移失败（可忽略）: {e}")


def _migrate_dm_tasks():
    """SQLite 迁移：确保 dm_tasks 表存在。

    新库由 create_all 自动建表，此迁移仅处理旧库（create_all 不会给已存在的库补表）。
    使用与现有迁移一致的原始 SQL，幂等可重复执行。
    """
    try:
        with engine.connect() as conn:
            conn.execute(text("""
                CREATE TABLE IF NOT EXISTS dm_tasks (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    device_id VARCHAR(100),
                    target_username VARCHAR(200) DEFAULT '',
                    content TEXT DEFAULT '',
                    status VARCHAR(20) DEFAULT 'pending',
                    scheduled_at DATETIME,
                    api_id VARCHAR(64) DEFAULT '',
                    result TEXT DEFAULT '',
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
                )
            """))
            conn.commit()
    except Exception as e:
        print(f"[migration] dm_tasks 表迁移失败（可忽略）: {e}")


def _migrate_nurture_plans():
    """SQLite 迁移：确保 nurture_plans 表存在。

    新库由 create_all 自动建表，此迁移仅处理旧库（create_all 不会给已存在的库补表）。
    使用与现有迁移一致的原始 SQL，幂等可重复执行。
    """
    try:
        with engine.connect() as conn:
            conn.execute(text("""
                CREATE TABLE IF NOT EXISTS nurture_plans (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name VARCHAR(200) DEFAULT '',
                    device_ids TEXT DEFAULT '[]',
                    account_ids TEXT DEFAULT '[]',
                    daily_actions TEXT DEFAULT '{}',
                    status VARCHAR(20) DEFAULT 'paused',
                    start_date DATETIME,
                    end_date DATETIME,
                    api_id VARCHAR(64) DEFAULT '',
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
                )
            """))
            conn.commit()
    except Exception as e:
        print(f"[migration] nurture_plans 表迁移失败（可忽略）: {e}")


def _migrate_public_users():
    """SQLite 迁移：确保 public_users 表存在（新库由 create_all 建，旧库补表）。幂等。"""
    try:
        with engine.connect() as conn:
            conn.execute(text("""
                CREATE TABLE IF NOT EXISTS public_users (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    aweme_id VARCHAR(100) DEFAULT '',
                    nickname VARCHAR(200) DEFAULT '',
                    avatar_url VARCHAR(500) DEFAULT '',
                    gender VARCHAR(20) DEFAULT '',
                    country VARCHAR(50) DEFAULT '',
                    followers INTEGER DEFAULT 0,
                    following_count INTEGER DEFAULT 0,
                    age INTEGER DEFAULT 0,
                    videos_count INTEGER DEFAULT 0,
                    signature TEXT DEFAULT '',
                    keyword TEXT DEFAULT '',
                    ai_tagged INTEGER DEFAULT 0,
                    contributed_by VARCHAR(64) DEFAULT '',
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
                )
            """))
            conn.execute(text("CREATE INDEX IF NOT EXISTS ix_public_users_aweme_id ON public_users(aweme_id)"))
            conn.execute(text("CREATE INDEX IF NOT EXISTS ix_public_users_ai_tagged ON public_users(ai_tagged)"))
            # 已存在表补新列（幂等）
            tables = [r[0] for r in conn.execute(text(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )).fetchall()]
            if "public_users" in tables:
                cols = [r[1] for r in conn.execute(text("PRAGMA table_info(public_users)")).fetchall()]
                if "following_count" not in cols:
                    conn.execute(text("ALTER TABLE public_users ADD COLUMN following_count INTEGER DEFAULT 0"))
                if "age" not in cols:
                    conn.execute(text("ALTER TABLE public_users ADD COLUMN age INTEGER DEFAULT 0"))
            conn.commit()
    except Exception as e:
        print(f"[migration] public_users 表迁移失败（可忽略）: {e}")


def _migrate_task_engine_columns():
    """SQLite 迁移：tasks 表补齐统一任务引擎字段。幂等。"""
    try:
        with engine.connect() as conn:
            tables = [r[0] for r in conn.execute(text(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )).fetchall()]
            if "tasks" in tables:
                cols = [r[1] for r in conn.execute(text("PRAGMA table_info(tasks)")).fetchall()]
                add_cols = {
                    "config": "TEXT DEFAULT '{}'",
                    "total": "INTEGER DEFAULT 0",
                    "done": "INTEGER DEFAULT 0",
                    "fail_count": "INTEGER DEFAULT 0",
                    "last_log": "TEXT DEFAULT ''",
                    "error": "TEXT DEFAULT ''",
                    "started_at": "DATETIME",
                    "next_dispatch_at": "DATETIME",
                }
                for name, ddl in add_cols.items():
                    if name not in cols:
                        conn.execute(text(f"ALTER TABLE tasks ADD COLUMN {name} {ddl}"))
                conn.commit()
    except Exception as e:
        print(f"[migration] tasks 引擎字段迁移失败（可忽略）: {e}")


def _migrate_proxy_nodes():
    """SQLite 迁移：确保 proxy_nodes 表存在 + device_bindings 补 country/last_ip 列。幂等。"""
    try:
        with engine.connect() as conn:
            conn.execute(text("""
                CREATE TABLE IF NOT EXISTS proxy_nodes (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name VARCHAR(200) DEFAULT '',
                    country VARCHAR(50) DEFAULT '',
                    protocol VARCHAR(30) DEFAULT '',
                    address VARCHAR(255) DEFAULT '',
                    port INTEGER DEFAULT 0,
                    config TEXT DEFAULT '',
                    remark TEXT DEFAULT '',
                    enabled INTEGER DEFAULT 1,
                    api_id VARCHAR(20) DEFAULT '',
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
                )
            """))
            conn.execute(text("CREATE INDEX IF NOT EXISTS ix_proxy_nodes_country ON proxy_nodes(country)"))
            tables = [r[0] for r in conn.execute(text(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )).fetchall()]
            if "device_bindings" in tables:
                cols = [r[1] for r in conn.execute(text("PRAGMA table_info(device_bindings)")).fetchall()]
                if "country" not in cols:
                    conn.execute(text("ALTER TABLE device_bindings ADD COLUMN country VARCHAR(50) DEFAULT ''"))
                if "last_ip" not in cols:
                    conn.execute(text("ALTER TABLE device_bindings ADD COLUMN last_ip VARCHAR(50) DEFAULT ''"))
            conn.commit()
    except Exception as e:
        print(f"[migration] proxy_nodes/device.country 迁移失败（可忽略）: {e}")


def _migrate_quick_commands():
    """SQLite 迁移：确保 quick_commands 表存在。

    新库由 create_all 自动建表，此迁移仅处理旧库（create_all 不会给已存在的库补表）。
    使用与现有迁移一致的原始 SQL，幂等可重复执行。
    """
    try:
        with engine.connect() as conn:
            conn.execute(text("""
                CREATE TABLE IF NOT EXISTS quick_commands (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name VARCHAR(200) DEFAULT '',
                    action VARCHAR(50) DEFAULT '',
                    params TEXT DEFAULT '{}',
                    description VARCHAR(500) DEFAULT '',
                    api_id VARCHAR(64) DEFAULT '',
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
                )
            """))
            conn.commit()
    except Exception as e:
        print(f"[migration] quick_commands 表迁移失败（可忽略）: {e}")


_migrate_tenant_columns()
_migrate_collected_data_columns()
# 租户隔离：为尚未有 api_id 的业务表补齐列并回填旧数据（collected_data 已有）
for _table in ("tasks", "task_executions", "timed_tasks", "feedback", "reply_templates", "media"):
    _migrate_add_api_id(_table)
_migrate_video_posts()
_migrate_dm_tasks()
_migrate_nurture_plans()
_migrate_quick_commands()
_migrate_public_users()
_migrate_task_engine_columns()
_migrate_proxy_nodes()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
