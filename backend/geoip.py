"""GeoIP 识别 — 把设备出口 IP 映射到国家

实现：ip-api.com 免费接口（http，无鉴权，45次/分钟），带进程内缓存 + 私网兜底。
失败返回 ""（不影响主流程）。
后续可平滑替换为离线库（ip2region/mmdb）。
"""

import json
import logging
import threading
import urllib.request

logger = logging.getLogger(__name__)

_cache = {}
_cache_lock = threading.Lock()

# 私网/保留网段：不识别
_PRIVATE_PREFIXES = ("127.", "10.", "192.168.", "172.16.", "172.17.", "172.18.", "172.19.",
                     "172.20.", "172.21.", "172.22.", "172.23.", "172.24.", "172.25.",
                     "172.26.", "172.27.", "172.28.", "172.29.", "172.30.", "172.31.",
                     "0.", "169.254.", "::1", "::")


def country_for_ip(ip: str) -> str:
    """返回 IP 所属国家中文名（如 美国/日本），失败返回 ''"""
    if not ip:
        return ""
    if any(ip.startswith(p) for p in _PRIVATE_PREFIXES):
        return ""
    with _cache_lock:
        if ip in _cache:
            return _cache[ip]
    try:
        req = urllib.request.Request(
            f"http://ip-api.com/json/{ip}?fields=status,countryCode,country",
            headers={"User-Agent": "xnow-backend"},
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode())
        if data.get("status") != "success":
            logger.warning(f"[geoip] {ip} lookup failed: {data}")
            return ""
        # countryCode -> 中文名（ip-api 返回英文 country，这里统一映射常用国家）
        code = data.get("countryCode", "")
        country = _CODE_TO_CN.get(code, data.get("country", ""))
        with _cache_lock:
            _cache[ip] = country
        return country
    except Exception as e:
        logger.warning(f"[geoip] {ip} lookup error: {e}")
        return ""


# countryCode -> 中文名（覆盖常用目标国；未命中返回英文名）
_CODE_TO_CN = {
    "US": "美国", "JP": "日本", "GB": "英国", "KR": "韩国", "VN": "越南",
    "TH": "泰国", "SG": "新加坡", "AE": "迪拜", "MY": "马来西亚", "BR": "巴西",
    "ID": "印度尼西亚", "AU": "澳大利亚", "IT": "意大利", "MX": "墨西哥",
    "DK": "丹麦", "TW": "台湾", "PH": "菲律宾", "DE": "德国", "FR": "法国",
    "ES": "西班牙", "NL": "荷兰", "CH": "瑞士", "SE": "瑞典", "NO": "挪威",
    "FI": "芬兰", "BE": "比利时", "AT": "奥地利", "IE": "爱尔兰", "PT": "葡萄牙",
    "GR": "希腊", "TR": "土耳其", "SA": "沙特", "QA": "卡塔尔", "OM": "阿曼",
    "KW": "科威特", "IN": "印度", "PK": "巴基斯坦", "BD": "孟加拉", "LK": "斯里兰卡",
    "NP": "尼泊尔", "CA": "加拿大", "AR": "阿根廷", "CL": "智利", "CO": "哥伦比亚",
    "PE": "秘鲁", "ZA": "南非", "EG": "埃及", "NG": "尼日利亚", "KE": "肯尼亚",
    "RU": "俄罗斯", "UA": "乌克兰", "PL": "波兰", "CZ": "捷克", "HU": "匈牙利",
    "RO": "罗马尼亚", "BG": "保加利亚", "HR": "克罗地亚", "RS": "塞尔维亚",
}
