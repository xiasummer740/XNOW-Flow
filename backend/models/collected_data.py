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
    collected_at = Column(DateTime(timezone=True), server_default=func.now())
