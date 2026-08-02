from sqlalchemy import Column, Integer, String, Text, DateTime
from sqlalchemy.sql import func
from database import Base


class QuickCommand(Base):
    """快捷指令库

    action: 指令 action（如 like/follow/smart_browse/register_account 等）
    params: JSON 字符串，指令参数
    """
    __tablename__ = "quick_commands"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(200), nullable=False, default="")     # 快捷指令名称
    action = Column(String(50), nullable=False, default="")    # 指令 action
    params = Column(Text, default="{}")                        # JSON object
    description = Column(String(500), default="")              # 描述
    api_id = Column(String(64), default="", index=True)        # 租户
    created_at = Column(DateTime(timezone=True), server_default=func.now())
