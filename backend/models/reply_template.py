from sqlalchemy import Column, Integer, String, DateTime, Text, Boolean
from sqlalchemy.sql import func
from database import Base

class ReplyTemplate(Base):
    __tablename__ = "reply_templates"

    id = Column(Integer, primary_key=True, index=True)
    api_id = Column(String(20), default="", index=True)   # 租户（关联用户）
    name = Column(String(200), nullable=False)
    content = Column(Text)
    match_type = Column(String(20), default="keyword")
    match_rule = Column(String(500))
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
