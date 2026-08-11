import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # 安全：不再提供可用的默认 SECRET_KEY，必须从 .env / 环境变量注入。
    # 若未配置则启动即抛错，杜绝"生产沿用开发默认密钥"。
    SECRET_KEY: str = ""
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
if not settings.SECRET_KEY:
    raise RuntimeError(
        "SECRET_KEY 未配置：请在 backend/.env 或环境变量设置强随机密钥，"
        "例如 `python -c \"import secrets; print(secrets.token_hex(32))\"`。"
    )
