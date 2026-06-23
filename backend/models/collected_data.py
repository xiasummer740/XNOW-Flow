from sqlalchemy import Column, Integer, String, Text, DateTime, func

from database import Base


class CollectedData(Base):
    __tablename__ = "collected_data"

    id = Column(Integer, primary_key=True, index=True)
    data_type = Column(String(50), nullable=False)
    content = Column(Text, nullable=False)
    source = Column(String(100))
    collected_at = Column(DateTime, server_default=func.now())
    created_at = Column(DateTime, server_default=func.now())
