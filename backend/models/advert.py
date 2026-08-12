from sqlalchemy import Column, Integer, String, Text, DateTime
from sqlalchemy.sql import func
from database import Base


class Advert(Base):
    """广告管理（PPT 参考产品广告管理模块）

    - 广告素材：标题/图片/链接/描述
    - 状态：active/disabled
    """
    __tablename__ = "adverts"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(200), default="")        # 广告标题
    image_url = Column(Text, default="")           # 广告图片
    link = Column(Text, default="")                # 跳转链接
    description = Column(Text, default="")         # 描述/文案
    status = Column(String(20), default="active")  # active/disabled
    api_id = Column(String(20), default="", index=True)  # 租户
    created_at = Column(DateTime(timezone=True), server_default=func.now())
