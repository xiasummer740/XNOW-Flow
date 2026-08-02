from sqlalchemy import Column, Integer, String, Text, DateTime
from sqlalchemy.sql import func
from database import Base


class VideoPost(Base):
    """定时发视频任务（自动发视频）"""
    __tablename__ = "video_posts"

    id = Column(Integer, primary_key=True, index=True)
    device_id = Column(String(100), index=True)          # 设备机器码
    video_url = Column(Text, default="")                  # 视频 URL / 素材链接
    title = Column(Text, default="")                      # 标题/文案
    category = Column(String(30), default="auto_post")    # 类型
    status = Column(String(20), default="pending")        # pending/processing/done/failed
    scheduled_at = Column(DateTime(timezone=True))        # 计划发布时间
    api_id = Column(String(64), default="", index=True)   # 租户
    result = Column(Text, default="")                     # 执行结果
    created_at = Column(DateTime(timezone=True), server_default=func.now())
