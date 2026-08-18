"""文本翻译端点 — 用 DASHSCOPE(qwen) 做实时翻译，供设备端私信页调用

POST /api/biz/v2/translate/
    { "text": "hello world", "target_lang": "中文", "device_id": "iphone_xxx" }
  → { "translated": "你好世界" }

鉴权（F14 修复，双兼容）：
- Web 后台：user JWT（Authorization Bearer）
- 设备端：X-Device-Secret header + body device_id（设备无 user JWT，走设备共享密钥）
"""
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from typing import Optional
import logging
import json
import urllib.request

from dependencies import get_optional_user
from models.user import User
from config import settings
from routers.ws import _extract_device_secret, _verify_device_auth

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/biz/v2", tags=["translate"])


class TranslateRequest(BaseModel):
    text: str
    target_lang: Optional[str] = "中文"
    device_id: Optional[str] = ""   # F14：设备端调用时携带，用于设备 secret 鉴权


@router.post("/translate/")
async def translate_text(
    req: TranslateRequest,
    request: Request,
    current_user: Optional[User] = Depends(get_optional_user),
    secret: str = Depends(_extract_device_secret),
):
    """翻译文本到目标语言（设备端私信实时翻译 / 后台可测）"""
    # F14：user JWT 与设备 secret 任一通过即可。无 user JWT → 必须是合法设备 secret。
    if current_user is None:
        device_id = (req.device_id or "").strip()
        if not (device_id and secret and _verify_device_auth(device_id, secret)):
            raise HTTPException(status_code=401, detail="unauthorized")
    text = (req.text or "").strip()
    if not text:
        return {"translated": ""}
    if len(text) > 2000:
        text = text[:2000]
    # 同语言/空目标 → 原样返回
    target = req.target_lang or "中文"

    if not settings.DASHSCOPE_API_KEY:
        return {"translated": text, "note": "DASHSCOPE_API_KEY 未配置"}

    prompt = f"请把下面内容翻译成{target}，只输出翻译结果，不要加解释或引号：\n{text}"
    body = {
        "model": settings.DASHSCOPE_MODEL or "qwen-vl-max",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 512,
        "temperature": 0.3,
    }
    try:
        req_obj = urllib.request.Request(
            settings.DASHSCOPE_BASE_URL + "/chat/completions",
            data=json.dumps(body).encode(),
            headers={
                "Content-Type": "application/json",
                "Authorization": "Bearer " + settings.DASHSCOPE_API_KEY,
            },
        )
        resp = json.loads(urllib.request.urlopen(req_obj, timeout=30).read())
        translated = resp["choices"][0]["message"]["content"].strip()
        # 去掉可能的引号包裹
        translated = translated.strip('"').strip("'")
        return {"translated": translated, "source": text, "target_lang": target}
    except Exception as e:
        logger.error(f"translate error: {e}")
        # 翻译失败降级：返回原文本（设备端可提示）
        return {"translated": text, "target_lang": target, "error": str(e)}
