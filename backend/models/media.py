from sqlalchemy import Column, Integer, String, DateTime, func

from database import Base


class Media(Base):
    __tablename__ = "media"

    id = Column(Integer, primary_key=True, index=True)
    filename = Column(String(255), nullable=False)
    filepath = Column(String(500), nullable=False)
    filetype = Column(String(50))
    filesize = Column(Integer, default=0)
    created_at = Column(DateTime, server_default=func.now())
