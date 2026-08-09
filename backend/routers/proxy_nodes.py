import base64
import json
import logging
import re
import urllib.parse

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from database import get_db
from models.proxy_node import ProxyNode
from schemas.proxy_node import (
    ProxyNodeResponse,
    ProxyNodeCreate,
    ProxyNodeUpdate,
    ProxyNodeImportRequest,
)
from schemas.common import MessageResponse
from dependencies import get_current_user
from models.user import User
from tenant import tenant_scope

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/biz/v2", tags=["proxy_nodes"])

# 节点名 -> 国家（常见词匹配；未命中用导入时 default_country）
_COUNTRY_KEYWORDS = [
    ("美国", ["美国", "美区", "美西", "美东", "🇺🇸", "us", "usa", "united states"]),
    ("日本", ["日本", "🇯🇵", "jp", "japan"]),
    ("英国", ["英国", "🇬🇧", "uk", "united kingdom"]),
    ("韩国", ["韩国", "🇰🇷", "kr", "korea"]),
    ("新加坡", ["新加坡", "🇸🇬", "sg", "singapore"]),
    ("香港", ["香港", "🇭🇰", "hk", "hong kong"]),
    ("台湾", ["台湾", "🇹🇼", "tw", "taiwan"]),
    ("德国", ["德国", "🇩🇪", "de", "germany"]),
    ("法国", ["法国", "🇫🇷", "fr", "france"]),
    ("澳大利亚", ["澳洲", "澳大利亚", "🇦🇺", "au", "australia"]),
    ("加拿大", ["加拿大", "🇨🇦", "ca", "canada"]),
    ("马来西亚", ["马来", "马来西亚", "🇲🇾", "my", "malaysia"]),
    ("泰国", ["泰国", "🇹🇭", "th", "thailand"]),
    ("越南", ["越南", "🇻🇳", "vn", "vietnam"]),
]


def _country_from_name(name: str, default: str = "") -> str:
    low = (name or "").lower()
    for cn, kws in _COUNTRY_KEYWORDS:
        for kw in kws:
            if kw.lower() in low:
                return cn
    return default


def _b64decode(s: str) -> str:
    """尝试 base64 解码（兼容 url-safe 与 padding）"""
    try:
        return base64.b64decode(s + "=" * (-len(s) % 4)).decode("utf-8", "ignore")
    except Exception:
        try:
            return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4)).decode("utf-8", "ignore")
        except Exception:
            return ""


def _parse_line(line: str, default_country: str) -> dict | None:
    """解析一行分享链接 -> 节点 dict（name/country/protocol/address/port/config）"""
    line = line.strip()
    if not line:
        return None
    low = line.lower()

    if low.startswith("vmess://"):
        payload = _b64decode(line[8:])
        try:
            obj = json.loads(payload)
            return {
                "name": obj.get("ps") or obj.get("name") or "",
                "protocol": "vmess",
                "address": obj.get("add", ""),
                "port": int(obj.get("port", 0) or 0),
                "config": line,
            }
        except Exception:
            return None

    if low.startswith("ss://"):
        body = line[5:]
        if "#" in body:
            body, frag = body.rsplit("#", 1)
        else:
            frag = ""
        name = urllib.parse.unquote(frag) or ""
        decoded = _b64decode(body)
        address = port = ""
        if decoded and "@" in decoded:
            addr_part = decoded.split("@")[-1]
        elif "@" in body:
            addr_part = body.split("@")[-1]
        else:
            addr_part = decoded or body
        if ":" in addr_part:
            h, p = addr_part.rsplit(":", 1)
            address, port = h, p
        return {"name": name, "protocol": "shadowsocks", "address": address,
                "port": int(port) if port and port.isdigit() else 0, "config": line}

    if low.startswith("trojan://"):
        body = line[9:]
        if "#" in body:
            body, frag = body.rsplit("#", 1)
        else:
            frag = ""
        name = urllib.parse.unquote(frag) or ""
        address = port = ""
        if "@" in body:
            addr_part = body.split("@")[-1]
            if ":" in addr_part:
                h, p = addr_part.rsplit(":", 1)
                address, port = h, p
        return {"name": name, "protocol": "trojan", "address": address,
                "port": int(port) if port and port.isdigit() else 0, "config": line}

    if low.startswith("vless://"):
        body = line[8:]
        if "#" in body:
            body, frag = body.rsplit("#", 1)
        else:
            frag = ""
        name = urllib.parse.unquote(frag) or ""
        m = re.search(r"@([^:]+):(\d+)", body)
        address = m.group(1) if m else ""
        port = m.group(2) if m else ""
        return {"name": name, "protocol": "vless", "address": address,
                "port": int(port) if port and port.isdigit() else 0, "config": line}
    return None


def _parse_subscription(text: str, default_country: str) -> list:
    """解析订阅内容 -> 节点 dict 列表

    支持三种形态：
    1. 纯分享链接行（ss/vmess/trojan/vless，每行一个）
    2. base64 编码的订阅（解码后为分享链接行）
    3. Clash YAML（proxies 段，正则提取，不依赖 yaml 库）
    """
    if not text:
        return []
    text = text.strip()

    nodes = []

    # 形态3：Clash YAML proxies 段
    if "proxies:" in text:
        for m in re.finditer(r"-\s*\{([^}]*)\}", text):
            kv = {}
            for k, v1, v2, v3 in re.findall(r"(\w+):\s*(?:\"([^\"]*)\"|'([^']*)'|([^,}\s]+))", m.group(1)):
                kv[k] = v1 or v2 or v3
            if kv.get("name") and (kv.get("server") or kv.get("address")):
                nodes.append({
                    "name": kv.get("name", ""),
                    "protocol": kv.get("type", ""),
                    "address": kv.get("server") or kv.get("address", ""),
                    "port": int(kv.get("port", 0) or 0),
                    "config": m.group(0),
                })
        if nodes:
            return nodes

    # 形态1/2：分享链接行或 base64
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if lines and not any("://" in ln for ln in lines):
        # 尝试 base64 解码整体
        decoded = _b64decode(text)
        if decoded and any("://" in ln for ln in decoded.splitlines()):
            lines = [ln for ln in decoded.splitlines() if ln.strip()]
    for ln in lines:
        node = _parse_line(ln, default_country)
        if node:
            nodes.append(node)
    return nodes


@router.get("/proxy-nodes/", response_model=dict)
def list_proxy_nodes(
    country: str = Query(None),
    only_enabled: bool = Query(False),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(ProxyNode)
    # admin 看全部，普通用户只看启用节点
    if current_user.role != "admin":
        query = query.filter(ProxyNode.enabled == True)
    else:
        scope = tenant_scope(ProxyNode, current_user)
        if scope is not None:
            query = query.filter(scope)
    if country:
        query = query.filter(ProxyNode.country == country)
    if only_enabled:
        query = query.filter(ProxyNode.enabled == True)
    nodes = query.order_by(ProxyNode.country, ProxyNode.name).all()
    return {"count": len(nodes), "results": [ProxyNodeResponse.model_validate(n) for n in nodes]}


@router.post("/proxy-nodes/", response_model=ProxyNodeResponse, status_code=201)
def create_proxy_node(
    req: ProxyNodeCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    node = ProxyNode(
        name=req.name, country=req.country, protocol=req.protocol,
        address=req.address, port=req.port, config=req.config,
        remark=req.remark, enabled=req.enabled,
    )
    if current_user.role != "admin":
        node.api_id = current_user.api_id or ""
    db.add(node)
    db.commit()
    db.refresh(node)
    return ProxyNodeResponse.model_validate(node)


@router.put("/proxy-nodes/{node_id}/", response_model=ProxyNodeResponse)
def update_proxy_node(
    node_id: int,
    req: ProxyNodeUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    node = db.query(ProxyNode).filter(ProxyNode.id == node_id).first()
    if not node:
        raise HTTPException(status_code=404, detail="节点不存在")
    data = req.model_dump(exclude_unset=True)
    for k, v in data.items():
        setattr(node, k, v)
    db.commit()
    db.refresh(node)
    return ProxyNodeResponse.model_validate(node)


@router.delete("/proxy-nodes/{node_id}/", response_model=MessageResponse)
def delete_proxy_node(
    node_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    node = db.query(ProxyNode).filter(ProxyNode.id == node_id).first()
    if not node:
        raise HTTPException(status_code=404, detail="节点不存在")
    db.delete(node)
    db.commit()
    return MessageResponse(message="节点已删除")


@router.post("/proxy-nodes/{node_id}/toggle/", response_model=ProxyNodeResponse)
def toggle_proxy_node(
    node_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    node = db.query(ProxyNode).filter(ProxyNode.id == node_id).first()
    if not node:
        raise HTTPException(status_code=404, detail="节点不存在")
    node.enabled = not node.enabled
    db.commit()
    db.refresh(node)
    return ProxyNodeResponse.model_validate(node)


@router.post("/proxy-nodes/import/", response_model=MessageResponse)
def import_proxy_nodes(
    req: ProxyNodeImportRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """订阅链接/内容批量导入：解析出节点并入库（同名+地址去重）"""
    if not req.subscription.strip():
        raise HTTPException(status_code=400, detail="订阅内容不能为空")
    nodes = _parse_subscription(req.subscription, req.default_country or "")
    if not nodes:
        raise HTTPException(status_code=400, detail="未能从订阅解析出节点，请检查格式（支持ss/vmess/trojan/vless分享链接、base64订阅、Clash YAML）")

    imported = skipped = 0
    api_id = current_user.api_id if current_user.role != "admin" else ""
    for n in nodes:
        country = _country_from_name(n.get("name", ""), req.default_country or "")
        exists = db.query(ProxyNode).filter(
            ProxyNode.address == n.get("address", ""),
            ProxyNode.name == n.get("name", ""),
        ).first()
        if exists:
            skipped += 1
            continue
        db.add(ProxyNode(
            name=n.get("name", ""),
            country=country,
            protocol=n.get("protocol", ""),
            address=n.get("address", ""),
            port=n.get("port", 0),
            config=n.get("config", ""),
            remark=req.remark or "",
            enabled=True,
            api_id=api_id,
        ))
        imported += 1
    db.commit()
    return MessageResponse(message=f"导入 {imported} 个节点，跳过重复 {skipped} 个")
