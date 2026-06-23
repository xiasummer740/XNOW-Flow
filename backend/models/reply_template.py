from sqlalchemy import Column, Integer, String, Text, DateTime, func

from database import Base


class ReplyTemplate(Base):
    __tablename__ = "reply_templates"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    content = Column(Text, nullable=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
