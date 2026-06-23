from fastapi import APIRouter

router = APIRouter(prefix="/api/collected-data", tags=["collected_data"])


@router.get("")
def collected_data_root():
    return {"message": "collected_data router placeholder"}
