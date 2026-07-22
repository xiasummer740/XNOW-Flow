from pydantic import BaseModel
from typing import Optional

class LoginRequest(BaseModel):
    username: str
    password: str

class UserInfo(BaseModel):
    id: int
    username: str
    is_active: bool
    api_id: Optional[str] = None

class LoginResponse(BaseModel):
    token: str
    user: UserInfo

class RegisterRequest(BaseModel):
    username: str
    password: str

class PasswordChangeRequest(BaseModel):
    old_password: str
    new_password: str
