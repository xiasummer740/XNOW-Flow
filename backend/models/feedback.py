from sqlalchemy import Column, Integer, String, DateTime, Text
from sqlalchemy.sql import func
from database import Base

class Feedback(Base):
    __tablename__ = "feedback"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(200))
    content = Column(Text)
    contact = Column(String(100))
    status = Column(String(20), default="pending")
    reply = Column(Text)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
