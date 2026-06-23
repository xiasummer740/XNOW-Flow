from pydantic import BaseModel
from typing import List, Optional, Generic, TypeVar

T = TypeVar("T")

class PaginatedResponse(BaseModel):
    count: int
    next: Optional[str] = None
    previous: Optional[str] = None
    results: list = []

class MessageResponse(BaseModel):
    message: str
