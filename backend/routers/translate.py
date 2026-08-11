"""文本翻译端点 — 用 DASHSCOPE(qwen) 做实时翻译，供设备端私信页调用

POST /api/biz/v2/translate/
    { "text": "hello world", "target_lang": "中文" }
  → { "translated": "你好世界" }
"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Optional
import logging
import json
import urllib.request

from dependencies import get_current_user
from models.user import User
from config import settings

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/biz/v2", tags=["translate"])


class TranslateRequest(BaseModel):
    text: str
    target_lang: Optional[str] = "中文"


@router.post("/translate/")
async def translate_text(
    req: TranslateRequest,
    current_user: User = Depends(get_current_user),
):
    """翻译文本到目标语言（设备端私信实时翻译）"""
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
