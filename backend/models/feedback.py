from sqlalchemy import Column, Integer, String, Text, DateTime, func

from database import Base


class Feedback(Base):
    __tablename__ = "feedbacks"

    id = Column(Integer, primary_key=True, index=True)
    content = Column(Text, nullable=False)
    submitter = Column(String(100))
    status = Column(String(20), default="pending")
    created_at = Column(DateTime, server_default=func.now())
