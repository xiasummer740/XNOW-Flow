def tenant_scope(model, current_user):
    """Return the SQLAlchemy filter for tenant isolation.
    Admin sees all; regular users see only their own api_id."""
    if current_user.role == "admin":
        return None
    return model.api_id == (current_user.api_id or "")


def ensure_owned(obj, current_user):
    """Raise 403 if obj.api_id doesn't match current_user (unless admin)."""
    if current_user.role == "admin":
        return True
    if getattr(obj, 'api_id', '') != (current_user.api_id or ''):
        from fastapi import HTTPException
        raise HTTPException(status_code=403, detail="无权访问该资源")


def resolve_owned_device(db, device_name, current_user):
    """解析设备名并校验归属，返回 DeviceBinding 或 None（设备不存在）。
    非 admin 用户操作他人设备 → 403。"""
    from fastapi import HTTPException
    from models.device import DeviceBinding
    if not device_name:
        raise HTTPException(status_code=400, detail="缺少设备")
    device = db.query(DeviceBinding).filter(DeviceBinding.name == device_name).first()
    if not device:
        return None
    if current_user.role != "admin":
        if (device.api_id or "") != (current_user.api_id or ""):
            raise HTTPException(status_code=403, detail="无权操作该设备")
    return device
