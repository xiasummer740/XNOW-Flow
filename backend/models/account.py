from sqlalchemy import Column, Integer, String, DateTime
from sqlalchemy.sql import func
from database import Base

class Account(Base):
    __tablename__ = "accounts"

    id = Column(Integer, primary_key=True, index=True)
    nickname = Column(String(100))
    username = Column(String(100))
    tk_number = Column(String(100))
    unique_id = Column(String(100))
    followers = Column(Integer, default=0)
    following_count = Column(Integer, default=0)
    video_count = Column(Integer, default=0)
    status = Column(String(20), default="active")
    region = Column(String(50))
    country = Column(String(50))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
