from pydantic import BaseModel
from typing import Optional

class LoginRequest(BaseModel):
    username: str
    password: str

class UserInfo(BaseModel):
    id: int
    username: str
    is_active: bool

class LoginResponse(BaseModel):
    token: str
    user: UserInfo

class PasswordChangeRequest(BaseModel):
    old_password: str
    new_password: str
