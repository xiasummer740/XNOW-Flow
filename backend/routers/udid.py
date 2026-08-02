"""UDID 签名申请 — 用户提交 UDID，管理员签名后提供扫码下载"""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from datetime import datetime
import logging

from database import get_db
from models.udid_request import UDIDRequest
from models.user import User
from dependencies import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/biz/v2", tags=["udid"])


def _serialize(r: UDIDRequest):
    return {
        "id": r.id, "udid": r.udid, "device_name": r.device_name,
        "email": r.email, "status": r.status, "ipa_url": r.ipa_url,
        "admin_note": r.admin_note,
        "created_at": r.created_at.isoformat() if r.created_at else None,
    }


# ========== 用户：提交/查询 UDID 申请（无需登录） ==========

@router.post("/udid/requests/")
def submit_udid(body: dict, db: Session = Depends(get_db)):
    """用户提交 UDID 申请（无需登录，公开）
    body: {udid, device_name?, email?}
    """
    udid = (body.get("udid") or "").strip()
    if not udid:
        raise HTTPException(status_code=400, detail="UDID 不能为空")
    # 已提交过 → 返回已有记录
    existing = db.query(UDIDRequest).filter(UDIDRequest.udid == udid).first()
    if existing:
        return _serialize(existing)
    req = UDIDRequest(
        udid=udid,
        device_name=(body.get("device_name") or "").strip(),
        email=(body.get("email") or "").strip(),
    )
    db.add(req)
    db.commit()
    db.refresh(req)
    return _serialize(req)


@router.get("/udid/requests/check/")
def check_udid(udid: str = Query(...), db: Session = Depends(get_db)):
    """用户查询自己 UDID 的签名状态"""
    req = db.query(UDIDRequest).filter(UDIDRequest.udid == udid).first()
    if not req:
        return {"status": "not_found", "message": "未提交申请"}
    return _serialize(req)


# ========== 管理员：管理 UDID 申请 ==========

@router.get("/udid/admin/")
def list_udid_requests(
    limit: int = Query(100, ge=1, le=500),
    status: str = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """管理员查看 UDID 申请列表"""
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="仅管理员可查看")
    query = db.query(UDIDRequest)
    if status:
        query = query.filter(UDIDRequest.status == status)
    total = query.count()
    items = query.order_by(UDIDRequest.id.desc()).limit(limit).all()
    return {"count": total, "results": [_serialize(r) for r in items]}


@router.post("/udid/admin/{request_id}/sign/")
def sign_udid_request(
    request_id: int,
    body: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """管理员标记已签名 + 提供 IPA 下载链接"""
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="仅管理员可操作")
    req = db.query(UDIDRequest).filter(UDIDRequest.id == request_id).first()
    if not req:
        raise HTTPException(status_code=404, detail="申请不存在")
    req.status = "signed"
    req.ipa_url = body.get("ipa_url") or ""
    req.admin_note = body.get("admin_note") or ""
    req.signed_at = datetime.utcnow()
    db.commit()
    return _serialize(req)


@router.post("/udid/admin/{request_id}/reject/")
def reject_udid_request(
    request_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """管理员拒绝申请"""
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="仅管理员可操作")
    req = db.query(UDIDRequest).filter(UDIDRequest.id == request_id).first()
    if not req:
        raise HTTPException(status_code=404, detail="申请不存在")
    req.status = "rejected"
    db.commit()
    return _serialize(req)
