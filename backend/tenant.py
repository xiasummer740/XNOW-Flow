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
