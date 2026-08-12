from sqlalchemy import Column, Integer, String, DateTime, Text
from sqlalchemy.sql import func
from database import Base


class PublicUser(Base):
    """公共用户库（跨租户共享的脱敏用户数据池）

    - 仅存 TikTok 公开资料（昵称/头像/性别/国家/粉丝数/签名），不含密码/token/邮箱/手机
    - aweme_id 全局去重键
    - ai_tagged 标记是否已做 AI 头像打标（keyword 存标签）
    - contributed_by 记录投喂者租户（仅溯源，不用于查询隔离）
    """
    __tablename__ = "public_users"

    id = Column(Integer, primary_key=True, index=True)
    aweme_id = Column(String(100), default="", index=True)   # TikTok 用户 ID（全局去重）
    nickname = Column(String(200), default="")
    avatar_url = Column(String(500), default="")             # 头像 URL（供 AI 打标）
    gender = Column(String(20), default="")                  # male/female/unknown
    country = Column(String(50), default="")                 # 国家
    followers = Column(Integer, default=0)                   # 粉丝数
    following_count = Column(Integer, default=0)             # 关注数（PPT 公共库字段）
    age = Column(Integer, default=0)                         # 年龄（PPT 公共库字段）
    videos_count = Column(Integer, default=0)                # 作品数
    signature = Column(Text, default="")                     # 签名
    keyword = Column(Text, default="")                       # AI 打标标签（逗号分隔）
    ai_tagged = Column(Integer, default=0)                   # 0/1 是否已 AI 打标
    contributed_by = Column(String(64), default="")          # 投喂者租户 api_id（溯源）
    created_at = Column(DateTime(timezone=True), server_default=func.now())
