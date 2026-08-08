import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    SECRET_KEY: str = "xnow-secret-key-change-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440  # 24h
    DATABASE_URL: str = "sqlite:///./data/xnow.db"
    UPLOAD_DIR: str = "./data/uploads"
    # 公共用户库 AI 头像打标（qwen-vl / DashScope 兼容 OpenAI 模式）
    DASHSCOPE_API_KEY: str = ""
    DASHSCOPE_BASE_URL: str = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    DASHSCOPE_MODEL: str = "qwen-vl-max"

    class Config:
        env_file = ".env"

settings = Settings()
