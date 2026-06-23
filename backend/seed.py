"""
种子数据 — 初始化测试数据
运行: python seed.py
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
import os

# Ensure data directory exists
os.makedirs("./data", exist_ok=True)

# 创建表
Base.metadata.create_all(bind=engine)
db = SessionLocal()

try:
    # 1. 管理员用户 (admin / admin)
    if not db.query(User).filter(User.username == "admin").first():
        admin = User(
            username="admin",
            password_hash=hashlib.sha256("admin".encode()).hexdigest(),
            is_active=True,
        )
        db.add(admin)
    else:
        # 已有 admin 用户，更新密码
        user = db.query(User).filter(User.username == "admin").first()
        user.password_hash = hashlib.sha256("admin".encode()).hexdigest()

    # 兼容旧版 yk0417 用户
    if db.query(User).filter(User.username == "yk0417").first():
        old = db.query(User).filter(User.username == "yk0417").first()
        db.delete(old)

    # 2. 设备
    if db.query(DeviceBinding).count() == 0:
        now = datetime.utcnow()
        device_data = [
            ("iPhone-8-01", "iPhone 8 (黑)", "idle", True, 3, "TikTok 32.5.0"),
            ("iPhone-8-02", "iPhone 8 (白)", "executing", True, 2, "TikTok 32.5.0"),
            ("iPhone-8-03", "iPhone 8 (红)", "online", True, 1, "TikTok 32.4.0"),
            ("iPhone-11-01", "iPhone 11", "idle", True, 5, "TikTok 32.5.0"),
            ("iPhone-12-01", "iPhone 12", "offline", False, 0, "—"),
        ]
        for i, (name, device_name, status, online, acct_count, app_ver) in enumerate(device_data):
            d = DeviceBinding(
                name=name,
                device_name=device_name,
                status=status,
                online=online,
                account_count=acct_count,
                last_online=now - timedelta(minutes=(i + 1) * 30),
                app_version=app_ver,
            )
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
        now = datetime.utcnow()
        tasks = [
            Task(type="follow", name="批量关注-科技博主", status="success", target="科技领域TOP100", device="iPhone-8-01", progress=100),
            Task(type="like", name="批量点赞-热门视频", status="running", target="推荐页视频", device="iPhone-8-02", progress=65),
            Task(type="comment", name="批量评论-产品推广", status="pending", target="产品测评视频", device="iPhone-8-03", progress=0),
            Task(type="collect", name="数据采集-竞品分析", status="success", target="竞品账号粉丝", device="iPhone-11-01", progress=100),
        ]
        for i, t in enumerate(tasks):
            t.created_at = now - timedelta(hours=(i + 1) * 3)
            db.add(t)

    # 5. 任务执行记录
    if db.query(TaskExecution).count() == 0:
        now = datetime.utcnow()
        for i in range(20):
            statuses = ["success", "success", "success", "failed", "success"]
            st = statuses[i % len(statuses)]
            exec = TaskExecution(
                task_name=f"任务-{i+1}",
                type=["follow", "like", "comment", "collect", "dm"][i % 5],
                status=st,
                device=f"iPhone-8-{(i % 3) + 1:02d}",
                account=f"account_{i+1}",
                target=f"https://www.tiktok.com/@{['user', 'creator', 'brand'][i % 3]}_{i+1}",
                result="成功执行" if st == "success" else "网络超时",
                started_at=now - timedelta(hours=i * 2),
                finished_at=now - timedelta(hours=i * 2 - 1) if st == "success" else None,
                duration=30 + i * 5 if st == "success" else 0,
            )
            db.add(exec)

    # 6. 定时任务
    if db.query(TimedTask).count() == 0:
        timed_tasks = [
            TimedTask(name="每日采集-用户数据", cron="0 2 * * *", task_type="数据采集", enabled=True, last_run=datetime.utcnow() - timedelta(days=1), next_run=datetime.utcnow()),
            TimedTask(name="批量关注任务", cron="0 9 * * 1-5", task_type="批量操作", enabled=True, last_run=datetime.utcnow() - timedelta(days=1)),
            TimedTask(name="评论采集-每小时", cron="0 * * * *", task_type="数据采集", enabled=False),
            TimedTask(name="素材同步", cron="0 3 */2 * *", task_type="系统维护", enabled=True, last_run=datetime.utcnow() - timedelta(days=1)),
        ]
        for t in timed_tasks:
            db.add(t)

    # 7. 公告
    if db.query(Announcement).count() == 0:
        announcements = [
            Announcement(title="系统维护通知 6/25", content="6月25日凌晨2:00-4:00进行服务器升级", priority="high", is_pinned=True),
            Announcement(title="新版本功能上线", content="新增批量私信模板功能，支持自定义话术", priority="normal", is_pinned=False),
            Announcement(title="使用规范提醒", content="请勿在短时间内大批量操作，避免触发风控", priority="normal", is_pinned=True),
        ]
        for a in announcements:
            db.add(a)

    # 8. 反馈
    if db.query(Feedback).count() == 0:
        feedbacks = [
            Feedback(title="建议增加定时发布功能", content="希望能支持定时发布作品", contact="admin@xnow.com", status="pending"),
            Feedback(title="设备连接不稳定", content="iPhone 8 经常断连", contact="user@test.com", status="resolved", reply="已优化 WebSocket 重连机制"),
        ]
        for f in feedbacks:
            db.add(f)

    # 9. 回复模板
    if db.query(ReplyTemplate).count() == 0:
        templates = [
            ReplyTemplate(name="通用感谢回复", content="感谢你的关注！\U0001f389", match_type="keyword", match_rule="感谢,谢谢,thx"),
            ReplyTemplate(name="产品咨询回复", content="详情请查看我们的主页链接~", match_type="keyword", match_rule="多少钱,价格,怎么买,how much"),
            ReplyTemplate(name="合作咨询回复", content="商务合作请联系：business@xnow.com", match_type="keyword", match_rule="合作,商务,推广"),
        ]
        for t in templates:
            db.add(t)

    db.commit()
    print("Seed data inserted successfully!")
except Exception as e:
    db.rollback()
    print(f"Error: {e}")
    raise
finally:
    db.close()
