from fastapi import APIRouter

router = APIRouter(prefix="/api/reply-templates", tags=["reply_templates"])


@router.get("")
def reply_templates_root():
    return {"message": "reply_templates router placeholder"}
