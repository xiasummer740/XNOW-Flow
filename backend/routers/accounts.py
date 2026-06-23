from fastapi import APIRouter

router = APIRouter(prefix="/api/accounts", tags=["accounts"])


@router.get("")
def accounts_root():
    return {"message": "accounts router placeholder"}
