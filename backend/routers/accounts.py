from fastapi import APIRouter, Depends, Query, HTTPException, UploadFile, File
from sqlalchemy.orm import Session
from sqlalchemy import or_
from typing import Optional
import json, csv, io, logging

from database import get_db, SessionLocal
from models.account import Account
from models.device import DeviceBinding
from schemas.account import (
    AccountResponse, AccountImportRequest,
    AccountBatchImportRequest, AccountDispatchRequest,
)
from schemas.common import PaginatedResponse, MessageResponse
from dependencies import get_current_user
from models.user import User
from tenant import tenant_scope, ensure_owned

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/biz/v2", tags=["accounts"])


# ==================== 查询 ====================


@router.get("/accounts/", response_model=PaginatedResponse)
def list_accounts(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    search: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    device_id: Optional[str] = Query(None, description="按绑定设备筛选"),
    has_credentials: Optional[bool] = Query(None, description="是否有登录凭证"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(Account)

    # 租户隔离：非 admin 只能看自己的账号
    scope = tenant_scope(Account, current_user)
    if scope is not None:
        query = query.filter(scope)

    if search:
        query = query.filter(
            or_(
                Account.nickname.contains(search),
                Account.aweme_number.contains(search),
                Account.phone.contains(search),
                Account.username.contains(search),
                Account.remark.contains(search),
            )
        )

    if status and status != "all":
        query = query.filter(Account.status == status)

    if device_id:
        query = query.filter(Account.device_id == device_id)

    total = query.count()
    accounts = query.order_by(Account.id.desc()).offset(offset).limit(limit).all()
    results = [AccountResponse.from_orm_with_creds(a) for a in accounts]

    # 如果有 has_credentials 筛选，在 Python 层过滤
    if has_credentials is not None:
        results = [r for r in results if r.has_credentials == has_credentials]
        # total 也需要重新计算（粗略处理）
        # 精确 count 太复杂，这里取过滤后的长度
        total = len(results)

    return PaginatedResponse(count=total, results=results)


@router.get("/accounts/stats/")
def account_stats(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    accounts_query = db.query(Account)
    scope = tenant_scope(Account, current_user)
    if scope is not None:
        accounts_query = accounts_query.filter(scope)
    accounts = accounts_query.all()
    with_creds = 0
    for a in accounts:
        try:
            c = json.loads(a.credentials or "{}")
            if c.get("password") or c.get("cookies") or c.get("token"):
                with_creds += 1
        except (json.JSONDecodeError, TypeError):
            pass
    return {
        "total": len(accounts),
        "active": sum(1 for a in accounts if a.status == "active"),
        "risk_control": sum(1 for a in accounts if a.status == "risk_control"),
        "offline": sum(1 for a in accounts if a.status not in ("active", "executing", "risk_control")),
        "with_credentials": with_creds,
        "today_fans_gain": 0,
    }


@router.get("/accounts/{account_id}/")
def get_account(
    account_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    account = db.query(Account).filter(Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="账号不存在")
    ensure_owned(account, current_user)
    return AccountResponse.from_orm_with_creds(account)


@router.patch("/accounts/{account_id}/")
def update_account(
    account_id: int,
    updates: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    account = db.query(Account).filter(Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="账号不存在")
    ensure_owned(account, current_user)
    for key, value in updates.items():
        if hasattr(account, key):
            setattr(account, key, value)
    db.commit()
    db.refresh(account)
    return AccountResponse.from_orm_with_creds(account)


# ==================== 导入 ====================


@router.post("/accounts/import/", response_model=AccountResponse, status_code=201)
def import_account(
    req: AccountImportRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """导入单个账号（支持密码/cookies/token）"""
    data = req.to_orm_dict()
    account = Account(**data)
    if current_user.role != "admin":
        account.api_id = current_user.api_id or ""
    db.add(account)
    db.commit()
    db.refresh(account)
    logger.info(f"导入账号: {account.nickname or account.username} (id={account.id})")
    return AccountResponse.from_orm_with_creds(account)


@router.post("/accounts/batch-import/", response_model=PaginatedResponse, status_code=201)
def batch_import_accounts(
    file: Optional[UploadFile] = File(None, description="CSV 文件（可选）"),
    body: Optional[AccountBatchImportRequest] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """批量导入账号。支持两种方式：
    - body: JSON 数组
    - file: CSV 文件（列名与 AccountImportRequest 字段一致）
    """
    imported = []

    # 方式1: JSON body
    if body and body.accounts:
        for req in body.accounts:
            data = req.to_orm_dict()
            acct = Account(**data)
            if current_user.role != "admin":
                acct.api_id = current_user.api_id or ""
            db.add(acct)
            imported.append(data)
        db.commit()

    # 方式2: CSV 文件
    if file and file.filename:
        content = file.file.read().decode("utf-8-sig")
        reader = csv.DictReader(io.StringIO(content))
        for row in reader:
            req = AccountImportRequest(**row)
            data = req.to_orm_dict()
            acct = Account(**data)
            if current_user.role != "admin":
                acct.api_id = current_user.api_id or ""
            db.add(acct)
            imported.append(data)
        db.commit()

    if not imported:
        raise HTTPException(status_code=400, detail="未提供任何账号数据")

    logger.info(f"批量导入 {len(imported)} 个账号")
    # 重新查出来返回
    accounts = db.query(Account).order_by(Account.id.desc()).limit(len(imported)).all()
    results = [AccountResponse.from_orm_with_creds(a) for a in accounts]
    return PaginatedResponse(count=len(results), results=results)


# ==================== 删除 ====================


@router.delete("/accounts/{account_id}/", response_model=MessageResponse)
def delete_account(
    account_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    account = db.query(Account).filter(Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="账号不存在")
    ensure_owned(account, current_user)
    db.delete(account)
    db.commit()
    logger.info(f"删除账号 id={account_id}")
    return MessageResponse(message="删除成功")


@router.post("/accounts/batch-delete/", response_model=MessageResponse)
def batch_delete_accounts(
    data: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    account_ids = data.get("account_ids", [])
    if not account_ids:
        raise HTTPException(status_code=400, detail="未指定删除的账号")
    accounts = db.query(Account).filter(Account.id.in_(account_ids)).all()
    deleted = 0
    for acc in accounts:
        ensure_owned(acc, current_user)
        db.delete(acc)
        deleted += 1
    db.commit()
    logger.info(f"批量删除 {deleted} 个账号")
    return MessageResponse(message=f"删除 {deleted} 个账号成功")


# ==================== 分配到设备 ====================


@router.post("/accounts/dispatch/", response_model=MessageResponse)
def dispatch_accounts(
    req: AccountDispatchRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """分配账号到指定设备"""
    device = db.query(DeviceBinding).filter(
        DeviceBinding.name == req.device_id
    ).first()
    if not device:
        raise HTTPException(status_code=404, detail="设备不存在")
    ensure_owned(device, current_user)

    accounts_query = db.query(Account).filter(Account.id.in_(req.account_ids))
    scope = tenant_scope(Account, current_user)
    if scope is not None:
        accounts_query = accounts_query.filter(scope)
    accounts = accounts_query.all()
    if not accounts:
        raise HTTPException(status_code=404, detail="未找到指定账号")

    for acc in accounts:
        acc.device_id = req.device_id

    device.account_count = len(accounts)
    db.commit()
    logger.info(f"分配 {len(accounts)} 个账号到设备 {req.device_id}")
    return MessageResponse(message=f"已分配 {len(accounts)} 个账号到 {req.device_id}")
