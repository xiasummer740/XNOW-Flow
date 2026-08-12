from sqlalchemy import Column, Integer, String, DateTime, Text
from sqlalchemy.sql import func
from database import Base

class CollectedData(Base):
    __tablename__ = "collected_data"

    id = Column(Integer, primary_key=True, index=True)
    source = Column(String(100))
    source_type = Column(String(50))
    content = Column(Text)
    author = Column(String(100))
    url = Column(String(500))
    # 增强字段（采集数据增强 PPT 特性）
    gender = Column(String(20), default="")          # male/female/unknown
    region = Column(String(50), default="")          # 地区
    followers = Column(Integer, default=0)           # 粉丝数
    following_count = Column(Integer, default=0)     # 关注数（PPT 公共库字段）
    age = Column(Integer, default=0)                 # 年龄（PPT 公共库字段）
    aweme_id = Column(String(100), default="")       # TikTok 用户 ID（去重用）
    group_name = Column(String(100), default="未分组")  # 数据分组
    api_id = Column(String(64), default="", index=True)  # 租户隔离
    remark = Column(Text, default="")                # 备注
    dedupe_key = Column(String(200), default="")     # 去重键（如 aweme_id 或 username）
    collected_at = Column(DateTime(timezone=True), server_default=func.now())
