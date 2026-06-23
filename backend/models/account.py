from sqlalchemy import Column, Integer, String, DateTime, Boolean, Text, BigInteger
from sqlalchemy.sql import func
from database import Base

class Account(Base):
    __tablename__ = "accounts"

    id = Column(Integer, primary_key=True, index=True)
    # Basic info
    nickname = Column(String(200))                        # 昵称
    username = Column(String(200))                         # 用户名
    aweme_id = Column(String(100), unique=True)           # 抖音ID
    aweme_number = Column(String(100))                    # TK号
    unique_id = Column(String(100))                       # 唯一标识
    avatar_url = Column(Text, default="")                 # 头像
    # Stats
    followers = Column(Integer, default=0)                # 粉丝数
    fans_count = Column(Integer, default=0)               # 粉丝数(别名)
    following_count = Column(Integer, default=0)          # 关注数
    digg_count = Column(Integer, default=0)               # 获赞数
    video_count = Column(Integer, default=0)              # 作品数
    friends_count = Column(Integer, default=0)            # 好友数
    diamond = Column(Integer, default=0)                  # 钻石
    health_score = Column(Integer, default=100)           # 健康分(0-100)
    # Profile
    signature = Column(Text, default="")                  # 签名
    web_url = Column(String(500), default="")             # 主页链接
    # Status
    status = Column(String(20), default="active")         # active/risk_control/banned/offline
    # Device & App
    device_id = Column(String(255), default="")           # 绑定设备
    bundle_id = Column(String(100), default="")           # 包名
    # Region
    region = Column(String(50))
    country = Column(String(50))
    act_country = Column(String(50), default="")          # 操作国家
    act_language = Column(String(20), default="")         # 操作语言
    act_city = Column(String(100), default="")
    act_sex = Column(Integer, default=0)
    act_age = Column(Integer, default=0)
    # Contact
    phone = Column(String(50), default="")
    email = Column(String(200), default="")
    has_2fa = Column(Boolean, default=False)
    is_email_bound = Column(Boolean, default=False)
    is_phone_bound = Column(Boolean, default=False)
    # Meta
    tags = Column(Text, default="[]")                     # JSON array
    remark = Column(Text, default="")                     # 备注
    register_time = Column(BigInteger, default=0)         # 注册时间戳
    source = Column(String(50), default="auto")           # 来源
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
