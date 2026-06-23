import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    SECRET_KEY: str = "xnow-secret-key-change-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440  # 24h
    DATABASE_URL: str = "sqlite:///./data/xnow.db"
    UPLOAD_DIR: str = "./data/uploads"

    class Config:
        env_file = ".env"

settings = Settings()
