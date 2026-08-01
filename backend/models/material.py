from sqlalchemy import Column, Integer, String, Text, Boolean, DateTime
from sqlalchemy.sql import func
from database import Base


class MaterialGroup(Base):
    """素材分组（头像/昵称/签名/链接 等）"""
    __tablename__ = "material_groups"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)            # 分组名
    category = Column(String(30), default="nickname")     # avatar/nickname/signature/link/title/comment
    description = Column(Text, default="")
    api_id = Column(String(20), default="", index=True)   # 租户
    item_count = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class Material(Base):
    """素材条目"""
    __tablename__ = "materials"

    id = Column(Integer, primary_key=True, index=True)
    group_id = Column(Integer, index=True)                # 所属分组
    category = Column(String(30), default="nickname")     # avatar/nickname/signature/link/title/comment
    content = Column(Text, default="")                    # 文本内容（昵称/签名/链接/文案）
    image_url = Column(Text, default="")                  # 头像素材图 URL
    status = Column(String(20), default="active")         # active/disabled
    api_id = Column(String(20), default="", index=True)   # 租户
    used_count = Column(Integer, default=0)               # 使用次数
    created_at = Column(DateTime(timezone=True), server_default=func.now())
