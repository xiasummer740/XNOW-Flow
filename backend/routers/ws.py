from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect, Request
import json
import logging
from datetime import datetime

from connection_manager import manager
from database import SessionLocal
from models.account import Account
from models.device import DeviceBinding

logger = logging.getLogger(__name__)
router = APIRouter(tags=["websocket"])

# 最近一次 ui_scan 上报结果缓存（页面识别用；device_id -> {"count","elements","ts"}）
_last_ui_scan = {}
# 最近一次截图上报缓存（电脑端查看真机画面用；device_id -> {"image_base64","width","height","ts"}）
_last_screenshot = {}
# 控件地图沉淀（v1.4.92；device_id -> {page: {"elements":[...], "ts":..., "tab":..., "screen":...}}）
_last_control_map = {}


def _get_device_api_id(device_id: str) -> str:
    """查询设备所属租户 api_id"""
    try:
        db = SessionLocal()
        dev = db.query(DeviceBinding).filter(DeviceBinding.name == device_id).first()
        if dev and dev.api_id:
            return dev.api_id
        return "1"
    except Exception as e:
        logger.error(f"_get_device_api_id error: {e}")
        return "1"
    finally:
        db.close()


def _insert_collected_data(device_id: str, data: dict) -> int:
    """从设备采集结果插入 collected_data（带去重：同租户 dedupe_key 已存在则跳过）

    data 形如: {"source_type": "comments", "users": ["u1", "u2"]}
    或        {"source_type": "comments", "users": [{"author": "u1", "aweme_id": "...", "gender": "...", "region": "...", "followers": 123}]}
    """
    from models.collected_data import CollectedData

    source_type = data.get("source_type") or "fans"
    users = data.get("users") or []
    if not isinstance(users, list) or not users:
        return 0

    api_id = _get_device_api_id(device_id)
    inserted = 0
    seen = set()  # 本次消息内的去重
    db = SessionLocal()
    try:
        for u in users:
            if isinstance(u, dict):
                author = u.get("author") or u.get("nickname") or u.get("username") or ""
                aweme_id = u.get("aweme_id") or ""
                gender = u.get("gender") or ""
                region = u.get("region") or ""
                try:
                    followers = int(u.get("followers") or 0)
                except (TypeError, ValueError):
                    followers = 0  # 非数值兜底，避免 Integer 列写入崩溃
                try:
                    following_count = int(u.get("following_count") or u.get("following") or 0)
                except (TypeError, ValueError):
                    following_count = 0
                try:
                    age = int(u.get("age") or 0)
                except (TypeError, ValueError):
                    age = 0
                remark = u.get("remark") or ""
                url = u.get("url") or u.get("avatar_url") or ""  # 头像链接（公共库投喂依赖）
            else:
                author = str(u)
                aweme_id = ""
                gender = ""
                region = ""
                followers = 0
                following_count = 0
                age = 0
                remark = ""
                url = ""
            if not author and not aweme_id:
                continue
            dedupe_key = aweme_id or f"{source_type}:{author}"
            if dedupe_key in seen:
                continue
            exists = db.query(CollectedData).filter(
                CollectedData.dedupe_key == dedupe_key,
                CollectedData.api_id == api_id,
            ).first()
            if exists:
                seen.add(dedupe_key)
                continue
            db.add(CollectedData(
                source="device",
                source_type=source_type,
                content="",
                author=author,
                url=url,
                gender=gender,
                region=region,
                followers=followers,
                following_count=following_count,
                age=age,
                aweme_id=aweme_id,
                group_name="未分组",
                api_id=api_id,
                remark=remark,
                dedupe_key=dedupe_key,
            ))
            seen.add(dedupe_key)
            inserted += 1
        db.commit()
        if inserted:
            logger.info(f"Device {device_id} collected {inserted} users (type={source_type})")
    except Exception as e:
        logger.error(f"_insert_collected_data error: {e}")
    finally:
        db.close()
    return inserted


def _apply_account_update(account: Account, account_data: dict, device_id: str):
    """把设备上报字段写入既有账号（阻止越权字段）"""
    blocked = {"id", "api_id", "aweme_id", "created_at", "updated_at", "credentials"}
    for key, value in account_data.items():
        if key in blocked or not hasattr(account, key):
            continue
        setattr(account, key, value)
    account.device_id = device_id


def _mark_task_from_result(device_id: str, data: dict):
    """设备命令结果回填任务状态：/command/ 路由创建的 running 任务按执行结果标记 done/failed"""
    from models.task import Task
    action = data.get("action", "")
    status = data.get("status", "")
    if not action:
        return
    db = SessionLocal()
    try:
        task = (
            db.query(Task)
            .filter(Task.device == device_id, Task.type == action, Task.status == "running")
            .order_by(Task.id.desc())
            .first()
        )
        if task:
            # check_health 设备返回 status=active（健康）→ 视同成功；
            # 其余命令 status=success 才算成功。
            ok = status in ("success", "active")
            task.status = "done" if ok else "failed"
            task.progress = 100
            task.finished_at = datetime.utcnow()
            task.last_log = ("✅ " if ok else "❌ ") + str(data.get("message", ""))
            if not ok and data.get("message"):
                task.error = str(data.get("message", ""))
            db.commit()
    except Exception as e:
        logger.error(f"_mark_task_from_result error: {e}")
    finally:
        db.close()


def _upsert_account(device_id: str, account_data: dict):
    """从设备上报创建或更新账号记录（按租户隔离，防跨租户篡改）"""
    from sqlalchemy.exc import IntegrityError
    db = SessionLocal()
    try:
        aweme_id = account_data.get("aweme_id", "")
        if not aweme_id:
            return
        tenant_id = _get_device_api_id(device_id)

        # 按租户查找，避免篡改他人账号
        account = db.query(Account).filter(
            Account.aweme_id == aweme_id,
            Account.api_id == tenant_id,
        ).first()
        if account:
            _apply_account_update(account, account_data, device_id)
        else:
            account = Account(
                aweme_id=aweme_id,
                nickname=account_data.get("nickname", ""),
                unique_id=account_data.get("unique_id", ""),
                followers=account_data.get("followers", 0),
                following_count=account_data.get("following_count", 0),
                digg_count=account_data.get("digg_count", 0),
                video_count=account_data.get("video_count", 0),
                signature=account_data.get("signature", ""),
                avatar_url=account_data.get("avatar_url", ""),
                device_id=device_id,
                health_score=account_data.get("health_score", 100),
                status=account_data.get("status", "active"),
                source="device_report",
                api_id=tenant_id,  # 归属设备租户
            )
            db.add(account)

        try:
            db.commit()
        except IntegrityError:
            # 并发上报同 aweme_id：先查后插非原子，撞唯一约束 → 回滚后重查并更新
            db.rollback()
            logger.warning(f"[ws] _upsert_account IntegrityError for aweme_id={aweme_id}, re-querying")
            account = db.query(Account).filter(
                Account.aweme_id == aweme_id,
                Account.api_id == tenant_id,
            ).first()
            if account:
                _apply_account_update(account, account_data, device_id)
                db.commit()
            else:
                logger.error(f"[ws] _upsert_account re-query failed for aweme_id={aweme_id}")

        # 绑定设备到该账号
        if account is not None:
            device = db.query(DeviceBinding).filter(
                DeviceBinding.name == device_id
            ).first()
            if device:
                device.current_account_id = account.id
                db.commit()

    except Exception as e:
        logger.error(f"_upsert_account error: {e}")
    finally:
        db.close()


def _handle_device_message(device_id: str, msg: dict):
    """处理设备上报的消息（WebSocket 和 HTTP 轮询共用）"""
    msg_type = msg.get("type", "unknown")

    if msg_type == "status":
        status_data = msg.get("data", {})
        logger.info(f"Device {device_id} status received via HTTP")

        # 如果包含 api_id，更新设备
        api_id = status_data.get("api_id", "")
        device_code = status_data.get("device_code", "")
        if api_id:
            _mark_device_online(device_id, api_id, device_code)

        # 更新 App 版本（应用程序列）
        app_version = status_data.get("app_version", "")
        if app_version:
            db = SessionLocal()
            try:
                dev = db.query(DeviceBinding).filter(DeviceBinding.name == device_id).first()
                if dev:
                    dev.app_version = app_version
                    db.commit()
            except Exception as e:
                logger.error(f"update app_version error: {e}")
            finally:
                db.close()

        current_account = status_data.get("current_account")
        if current_account:
            _upsert_account(device_id, current_account)

    elif msg_type == "result":
        data = msg.get("data", {})
        logger.info(f"Device {device_id} result: {data}")
        # 回填远程指令任务状态（/command/ 路由创建的 running 任务 → done/success 或 failed）
        # 旧实现永不回填 + task_engine 又误判"无有效目标单元" → 后台所有指令显示失败（状态误报根因）
        if isinstance(data, dict) and data.get("action"):
            _mark_task_from_result(device_id, data)
        # 采集结果（collect_fans/collect_comments/collect_live_users 等）入库
        if isinstance(data, dict) and isinstance(data.get("users"), list):
            _insert_collected_data(device_id, data)

    elif msg_type == "touch_diag":
        # 触摸注入诊断（点击落点控件信息）— 用于验证远程指令是否点到正确元素
        logger.info(f"Device {device_id} touch_diag: {msg.get('data', {})}")

    elif msg_type == "scroll_event":
        # 页面滚动事件（TikTok feed 真的翻页时）— 用于验证远程滑动是否生效
        logger.info(f"Device {device_id} scroll_event: {msg.get('data', {})}")

    elif msg_type == "scroll_diag":
        # feed 翻页诊断（设备端是否找到 feed 视图/滚动到哪）— 用于排查滑动指令
        logger.info(f"Device {device_id} scroll_diag: {msg.get('data', {})}")

    elif msg_type == "state_diag":
        # 控件状态诊断（点击后按钮选中态/无障碍值）— 自验收点击是否生效
        logger.info(f"Device {device_id} state_diag: {msg.get('data', {})}")

    elif msg_type == "ui_scan":
        # UI 结构扫描（设备端视图树可交互控件清单）— 按元素定位操作
        data = msg.get("data", {})
        count = data.get("count", 0)
        logger.info(f"Device {device_id} ui_scan: {count} elements")
        for el in data.get("elements", []):
            logger.info(f"  UI [{el.get('class','?')}] x={el.get('x')} y={el.get('y')} frame={el.get('frame','')} "
                        f"acc_id={el.get('acc_id','')} acc_label={el.get('acc_label','')} sel={el.get('isSelected')}")
        # 缓存最近一次扫描结果，供页面识别/诊断读取
        _last_ui_scan[device_id] = {
            "count": count,
            "elements": data.get("elements", []),
            "ts": datetime.utcnow().isoformat(),
        }
        # 控件地图沉淀（v1.4.92）：按页累积，全盘扫描后即得参考表
        page = (data.get("page") or {}).get("page", "unknown")
        _last_control_map.setdefault(device_id, {})[page] = {
            "count": count,
            "elements": data.get("elements", []),
            "tab": data.get("tab"),
            "screen": data.get("screen"),
            "ts": datetime.utcnow().isoformat(),
        }

    elif msg_type == "screenshot":
        # 设备截图上报（base64，电脑端浏览器查看真机画面）— 只缓存最近一张
        data = msg.get("data", {})
        b64 = data.get("image_base64", "")
        logger.info(f"Device {device_id} screenshot: {len(b64)} b64 chars")
        _last_screenshot[device_id] = {
            "image_base64": b64,
            "width": data.get("width"),
            "height": data.get("height"),
            "ts": datetime.utcnow().isoformat(),
        }

    elif msg_type == "collect_result":
        data = msg.get("data", {})
        logger.info(f"Device {device_id} collect_result: {data.get('source_type', '')}")
        inserted = _insert_collected_data(device_id, data if isinstance(data, dict) else {})
        logger.info(f"Device {device_id} collect_result inserted {inserted} rows")

    elif msg_type == "account_update":
        account_data = msg.get("data", {})
        logger.info(f"Device {device_id} account update: {account_data.get('nickname', '')}")
        _upsert_account(device_id, account_data)

    elif msg_type == "account_list":
        accounts = msg.get("data", [])
        for acc_data in accounts:
            _upsert_account(device_id, acc_data)

    elif msg_type == "bind_info":
        bind_data = msg.get("data", {})
        device_code = bind_data.get("device_code", "")
        api_id = bind_data.get("api_id", "")
        logger.info(f"Device {device_id} bound: code={device_code}, api_id={api_id}")

        # 商用配额：首次绑定须有该设备的 active 卡，失败则不绑租户
        err = _mark_device_online(device_id, api_id, device_code)
        if err:
            logger.warning(f"Device {device_id} bind_info rejected: {err}")
            return

        # 更新设备记录（不改 name = 连接身份，防指令 key 失配）
        db = SessionLocal()
        try:
            dev = db.query(DeviceBinding).filter(DeviceBinding.name == device_id).first()
            if dev:
                # 只绑定首个租户：设备已绑定 api_id 时忽略设备上报的 api_id
                if not dev.api_id:
                    dev.api_id = api_id
                if device_code:
                    dev.device_code = device_code  # 编号存独立列，不改 name
                db.commit()
                logger.info(f"Device {device_id} updated with api_id={api_id}, code={device_code}")
        except Exception as e:
            logger.error(f"bind_info error: {e}")
        finally:
            db.close()

    elif msg_type == "crash_report":
        crash = msg.get("data", {}).get("crash", "")
        last_action = msg.get("data", {}).get("last_action", "")
        logger.error(f"🚨 Device {device_id} CRASH: {crash[:2000]} (last_action={last_action})")

    elif msg_type == "step":
        step = msg.get("data", {}).get("step", "")
        logger.info(f"▶️ Device {device_id} STEP: {step}")

    elif msg_type == "ping":
        pass  # HTTP 轮询的 ping 不需要回复

    else:
        logger.info(f"Device {device_id} unknown message type: {msg_type}")


import re

_UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)


def _extract_device_secret(request: Request, secret: str = "") -> str:
    """设备密钥双兼容解析：X-Device-Secret 请求头优先，query 参数兜底。

    v1.4.97 起设备端把密钥改走 header（避免进 server.log/代理日志明文泄露）。
    保留 query 兜底是让旧设备在后端升级后仍能连上，过渡期后移除。
    """
    return request.headers.get("X-Device-Secret") or secret


def _verify_device_auth(device_id: str, secret: str) -> bool:
    """验证设备请求的共享密钥

    - secret 必须是 UUID 格式（设备端 XN_DeviceSecret 生成 UUID）
    - 设备不存在: 必须带合法 secret 才能自动注册（secret 作为该设备密钥）
    - 设备存在且已绑定 secret: 恒定时间比较，必须匹配
    - 设备存在但未绑定 secret: 拒绝（旧宽松迁移期已结束，避免冒充）
    """
    if not device_id or not secret or not _UUID_RE.match(secret):
        return False
    try:
        db = SessionLocal()
        device = db.query(DeviceBinding).filter(
            DeviceBinding.name == device_id
        ).first()
        if not device:
            # 新设备必须带 UUID 格式 secret 注册
            device = DeviceBinding(
                name=device_id,
                device_name=device_id,
                device_id=device_id,
                status="online",
                online=True,
                is_online=True,
                account_count=0,
                device_secret=secret,
                last_online=datetime.utcnow(),
                app_version="—",
                added_by="系统",
            )
            db.add(device)
            db.commit()
            db.close()
            logger.info(f"Device {device_id} auto-registered with secret")
            return True
        if not device.device_secret:
            # 设备存在但未绑定 secret：拒绝（避免攻击者抢先绑定冒充）
            db.close()
            logger.warning(f"Device {device_id} has no secret bound, auth rejected")
            return False
        ok = _constant_time_eq(device.device_secret, secret)
        db.close()
        return ok
    except Exception as e:
        logger.error(f"_verify_device_auth error: {e}")
        return False


def _constant_time_eq(a: str, b: str) -> bool:
    """恒定时间字符串比较，防时序侧信道"""
    import hmac
    return hmac.compare_digest(a.encode(), b.encode())


def _mark_device_online(device_id: str, api_id: str = "", device_code: str = "", client_ip: str = ""):
    """标记设备在线（用于 HTTP 轮询设备）

    首次绑定 api_id 时执行商用配额校验（严格模式：设备须有 active 卡）。
    返回错误信息（str）或 None（成功）。配额不足时设备不绑定，保持原状态。
    """
    db = SessionLocal()
    try:
        device = db.query(DeviceBinding).filter(
            DeviceBinding.name == device_id
        ).first()
        if device:
            device.online = True
            device.is_online = True  # 前端用 is_online 判断在线
            device.status = "online"
            if client_ip and client_ip != device.last_ip:
                device.last_ip = client_ip  # 记录最近出口 IP（GeoIP 识别当前国家）
            # 只绑定首个租户：设备已绑定 api_id 时忽略上报值
            if api_id and not device.api_id:
                # 商用配额：首次绑定须有该设备的 active 卡（一卡一机）
                try:
                    from quota import ensure_device_bindable
                    ensure_device_bindable(db, device_id, api_id)
                    device.api_id = api_id
                except Exception as e:
                    logger.warning(f"Device {device_id} bind blocked: {e}")
                    db.rollback()
                    return str(getattr(e, "detail", e))
            # 机器码：设备唯一标识（用于区分多台设备）
            if not device.device_id:
                device.device_id = device_id
            device.last_online = datetime.utcnow()
        else:
            # 新设备自动注册：标记在线但不绑定租户（须先激活卡密 + 显式 bind_info）
            device = DeviceBinding(
                name=device_id,
                device_name=device_id,
                device_id=device_id,  # 机器码 = 设备唯一ID
                status="online",
                online=True,
                is_online=True,  # 前端用 is_online 判断在线
                account_count=0,
                api_id="",
                last_online=datetime.utcnow(),
                app_version="—",
                added_by="系统",
            )
            db.add(device)
            logger.info(f"Device {device_id} auto-registered via HTTP poll")
        db.commit()
    except Exception as e:
        logger.error(f"_mark_device_online error: {e}")
        return "内部错误"
    finally:
        db.close()
    return None


# ========== WebSocket 端点（向后兼容） ==========
@router.websocket("/ws/{device_id}")
async def device_websocket(device_id: str, ws: WebSocket, api_id: str = "", device_code: str = "", secret: str = ""):
    """设备 WebSocket 连接端点

    设备（iOS 插件）通过这个端点连接到后端。
    连接后保持长连接，接收指令并回传状态。
    api_id: 用户 API 标识
    device_code: 设备编号（1-20）
    secret: 设备共享密钥（鉴权，header 或 query）
    """
    # 设备鉴权（v1.4.97 起 header 优先，query 兜底）
    secret = ws.headers.get("X-Device-Secret") or secret
    if not _verify_device_auth(device_id, secret):
        await ws.close(code=4001, reason="unauthorized")
        return
    await manager.connect(device_id, ws, api_id=api_id, device_code=device_code)
    try:
        while True:
            # 等待设备发来的消息（状态更新、执行结果等）
            data = await ws.receive_text()
            try:
                msg = json.loads(data)
                msg_type = msg.get("type", "unknown")

                if msg_type == "status":
                    # 设备状态更新
                    status_data = msg.get("data", {})
                    logger.info(f"Device {device_id} status received")

                    # 如果包含账号信息，更新账号表
                    current_account = status_data.get("current_account")
                    if current_account:
                        _upsert_account(device_id, current_account)

                elif msg_type == "result":
                    # 任务执行结果回传
                    data = msg.get("data", {})
                    logger.info(f"Device {device_id} result: {data}")
                    # 回填远程指令任务状态（与 HTTP 轮询共用 helper）
                    if isinstance(data, dict) and data.get("action"):
                        _mark_task_from_result(device_id, data)
                    # 采集结果（collect_fans/collect_comments/collect_live_users 等）入库
                    if isinstance(data, dict) and isinstance(data.get("users"), list):
                        _insert_collected_data(device_id, data)

                elif msg_type == "collect_result":
                    data = msg.get("data", {})
                    logger.info(f"Device {device_id} collect_result: {data.get('source_type', '')}")
                    _insert_collected_data(device_id, data if isinstance(data, dict) else {})

                elif msg_type == "account_update":
                    # 设备上报账号信息
                    account_data = msg.get("data", {})
                    logger.info(f"Device {device_id} account update: {account_data.get('nickname', '')}")
                    _upsert_account(device_id, account_data)

                elif msg_type == "account_list":
                    # 设备上报多个账号列表
                    accounts = msg.get("data", [])
                    for acc_data in accounts:
                        _upsert_account(device_id, acc_data)

                elif msg_type == "bind_info":
                    # 设备绑定信息上报
                    bind_data = msg.get("data", {})
                    device_code = bind_data.get("device_code", "")
                    api_id = bind_data.get("api_id", "")
                    logger.info(f"Device {device_id} bound: code={device_code}, api_id={api_id}")
                    # 更新设备记录（不改 name = 连接身份，防指令 key 失配）
                    db = SessionLocal()
                    try:
                        dev = db.query(DeviceBinding).filter(DeviceBinding.name == device_id).first()
                        if dev:
                            # 只绑定首个租户：设备已绑定 api_id 时忽略设备上报的 api_id
                            if not dev.api_id:
                                dev.api_id = api_id
                            if device_code:
                                dev.device_code = device_code  # 编号存独立列，不改 name
                            db.commit()
                            logger.info(f"Device {device_id} updated with api_id={api_id}, code={device_code}")
                    except Exception as e:
                        logger.error(f"bind_info error: {e}")
                    finally:
                        db.close()
                    await ws.send_json({"type": "bind_info_ack", "data": {"status": "ok"}})

                elif msg_type == "ping":
                    # 心跳
                    await ws.send_json({"type": "pong"})

                else:
                    await ws.send_json({"type": "error", "message": f"Unknown type: {msg_type}"})

            except json.JSONDecodeError:
                await ws.send_json({"type": "error", "message": "Invalid JSON"})

    except WebSocketDisconnect:
        logger.info(f"Device {device_id} websocket disconnected")
    except Exception as e:
        logger.error(f"WebSocket error for {device_id}: {e}")
    finally:
        await manager.disconnect(device_id)


# ========== HTTP 轮询端点（避开 BH TikTok 长连接检测） ==========

@router.post("/ws/{device_id}")
async def device_http_post(device_id: str, request: Request, secret: str = Depends(_extract_device_secret)):
    """设备通过 HTTP POST 上报数据

    替代 WebSocket 的消息通道，每次请求短连接。
    设备定时 POST 上报状态/账号/结果，同时带回积压指令。
    需携带设备共享密钥（X-Device-Secret 请求头，旧版 query secret 兜底）鉴权。
    """
    # 设备鉴权
    if not _verify_device_auth(device_id, secret):
        from fastapi.responses import JSONResponse
        return JSONResponse(status_code=401, content={"detail": "unauthorized"})

    try:
        body = await request.json()
    except Exception:
        return {"status": "error", "message": "Invalid JSON"}

    msg_type = body.get("type", "unknown")

    # 处理消息（与 WebSocket 共用处理函数）
    _handle_device_message(device_id, body)

    # 标记设备最近活跃（更新 last_online + 出口 IP）
    api_id = body.get("data", {}).get("api_id", "") if isinstance(body.get("data"), dict) else ""
    _mark_device_online(device_id, api_id, client_ip=request.client.host if request.client else "")

    # 返回 pending 指令（如果有）
    pending = manager.dequeue_commands(device_id)
    response = {"status": "ok"}

    if msg_type == "bind_info":
        response["ack"] = {"type": "bind_info_ack", "data": {"status": "ok"}}

    if msg_type == "ping":
        response["pong"] = True

    if pending:
        # 如果有多条，一次只返回第一条，剩余的留在队列中
        # 但实际上 dequeue_commands 已经清空了队列
        # 所以额外的命令需要重新入队
        command = pending[0]
        if len(pending) > 1:
            for extra in pending[1:]:
                manager.enqueue_command(device_id, extra)
        response["command"] = command
        logger.info(f"Sent command to {device_id} via POST response: {command.get('action', 'unknown')}")

    return response


@router.get("/ws/{device_id}/poll")
async def device_http_poll(device_id: str, request: Request, secret: str = Depends(_extract_device_secret)):
    """设备轮询获取积压指令

    设备定时（每 5 秒）GET 此端点，获取服务端下发的指令。
    无指令时返回 204 No Content。
    需携带设备共享密钥（X-Device-Secret 请求头，旧版 query secret 兜底）鉴权。
    """
    # 设备鉴权
    if not _verify_device_auth(device_id, secret):
        from fastapi.responses import JSONResponse
        return JSONResponse(status_code=401, content={"detail": "unauthorized"})

    # 轮询也更新在线状态（前端用 is_online/last_online 判断设备在线）
    _mark_device_online(device_id, client_ip=request.client.host if request.client else "")

    pending = manager.dequeue_commands(device_id)
    if not pending:
        from fastapi.responses import Response
        return Response(status_code=204)

    # 一条一条返回，第一条直接返回，其余的重新入队
    command = pending[0]
    if len(pending) > 1:
        for extra in pending[1:]:
            manager.enqueue_command(device_id, extra)

    logger.info(f"Device {device_id} polled command: {command.get('action', 'unknown')}")
    return command
