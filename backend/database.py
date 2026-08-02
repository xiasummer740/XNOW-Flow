from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, DeclarativeBase

from config import settings

engine = create_engine(
    settings.DATABASE_URL,
    connect_args={"check_same_thread": False}  # SQLite only
)
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

            # device_bindings.device_code：绑定编号存独立列（不改name防丢指令）
            if "device_bindings" in tables:
                cols = [r[1] for r in conn.execute(text("PRAGMA table_info(device_bindings)")).fetchall()]
                if "device_code" not in cols:
                    conn.execute(text("ALTER TABLE device_bindings ADD COLUMN device_code VARCHAR(50) DEFAULT ''"))

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
_migrate_video_posts()
_migrate_dm_tasks()
_migrate_nurture_plans()
_migrate_quick_commands()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
