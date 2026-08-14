# -*- coding: utf-8 -*-
"""TikTok 页面识别：根据 ui_scan 控件数据判断当前页面 + 区分"固定控件/变量内容"。

纯函数模块，无 FastAPI/数据库依赖，后端接口与演示脚本均可复用。
输入 elements 元素形如:
    {"class": "AWEFeedVideoButton", "x": 382, "y": 390, "frame": "...",
     "acc_id": "feedLikeButton", "label": "Like video. 209 likes", "isSelected": false}
x/y 为控件中心点（窗口坐标）。屏幕 414x844，TikTok 内容窗口高 736。

识别思路（对应和祥哥对齐的方案）：
  1. 主证据 = 页面锚点（acc_id / 类名）加权投票，命中 ≥ 阈值才判中
  2. 屏外预加载 cell（y 超窗）一律不算
  3. 固定控件 = 有 acc_id 或强结构类名或固定文案；变量 = 动态文本（昵称/数字/描述）
"""
from __future__ import annotations

SCREEN_H = 736  # TikTok 内容窗口高度，y 超出视为屏外预加载

PAGE_TITLES = {
    "feed": "Feed 首页（For You）",
    "profile": "个人主页（Profile）",
    "inbox": "收件箱（Inbox）",
    "search": "搜索页（Search）",
    "friends": "朋友页（Friends）",
    "recorder": "录制/创作页（Recorder）",
    "other": "未知页面",
}

# 页面锚点签名：键 = acc_id 或类名，值 = 权重。优先用 acc_id（TikTok 官方无障碍标识，跨版本最稳）
PAGE_SIGNATURES = {
    "feed": {
        "top_tabs_recomend": 3,                # For You 顶部标签（只在 feed）
        "feedLikeButton": 3,                   # 点赞按钮（屏内）
        "exploretab_tabname_explore": 2,       # Explore 标签
        "TikTokFeedFadeScrollView": 1,         # feed 顶部标签滚动容器
        "nearby_tab_name": 1,
        "following": 1,
    },
    "profile": {
        "TTKProfileTabVideoButton_0": 3,       # Posts 作品标签
        "TTKProfileTabLikeButton_2": 2,        # Liked 标签
        "relation_info_following": 2,          # 关注数统计
        "relation_info_follower": 2,           # 粉丝数统计
        "relation_info_like": 2,               # 获赞数统计
        "header_avatar": 2,                    # 头像区
        "user_account_user_name": 1,           # @用户名
        "nav_bar_end_settings": 1,             # 设置按钮
    },
    "search": {
        "AWESearchBar": 3,                     # 搜索框（类名）
        "TTKSearchPressStatusButton": 2,       # 搜索按钮（类名）
        "TTKSearchBarRightButton": 2,          # 语音搜索
    },
    "inbox": {
        # 收件箱（真机 2026-08-14 确认）：无 acc_id，靠类名识别，均带 Inbox 专属前缀
        "TTKInboxActivityStatusView": 3,                # 顶栏活动状态（唯一）
        "TTKInboxActivityFrameEntranceCell": 2,         # 活动入口卡片（多条）
        "TTKInboxActivityFrameEntranceOrderingCell": 1, # 排序卡片
        "TTKFriendPermissionRequestCollectionViewCell": 1,  # 好友申请列表
    },
    "friends": {
        # 朋友页（真机 2026-08-14 确认）：顶部也有 AWESearchBar（找朋友），
        # 靠以下专属类名压过搜索误判（识别取最高分页面）
        "TTKFriendsFeedTableViewCell": 3,               # 朋友 feed 卡片（唯一）
        "TTKShareInviteFriendsRowView": 2,              # 分享/邀请朋友行
        "TTKRelationUserCardCollectionView": 1,         # 关系用户卡片流
    },
    "recorder": {
        # 录制/创作页（真机 2026-08-14 确认）：底部 + 按钮进入，acc_id 全部带专属前缀
        "recorderPageToolBarSwapCamera": 3,   # 切换镜头
        "recorderPageToolBarFlash": 2,        # 闪光灯
        "recorderPageToolBarCountDown": 2,    # 倒计时
        "recorderPageToolBarMicrophone": 2,   # 麦克风
        "recorderPageToolBarBeautify": 2,     # 美颜
        "recorderPageToolBarFilter": 2,       # 滤镜
        "recordPageCompleteButton": 3,        # 完成按钮
        "recordPageUploadButton": 2,          # 上传按钮
        "recordPageEffectsEntrance": 1,       # 特效入口
        "ratio": 1,                           # 画幅比例
    },
}

# 固定文案（跨页面不随内容变的 label）
FIXED_WORDS = {
    "home", "friends", "inbox", "profile", "create", "for you", "following", "explore",
    "stem", "nearby", "back", "search", "voice search", "posts", "private", "favorites",
    "liked", "add name", "switch accounts", "find friends", "close", "upload", "go live",
    "refresh", "loading", "live", "message",
}

# 强结构类名（无 acc_id 也视为固定骨架）
STRUCT_KEYWORDS = (
    "TabBar", "FeedTabItem", "SearchBar", "NavBar", "ProfileTab", "ProfileHeader",
    "AvatarContainer", "FadeScrollView", "MaskWindow", "LayoutContainer",
)


def _num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0


def _in_screen(y):
    return 0 <= _num(y) <= SCREEN_H


def _is_fixed(acc, cls, label):
    if acc:
        return True  # 有官方无障碍标识 → 结构锚点
    if label and label.strip().lower() in FIXED_WORDS:
        return True
    if any(k in (cls or "") for k in STRUCT_KEYWORDS):
        return True
    return False


def _is_var(label):
    if not label:
        return False
    t = label.strip()
    if not t:
        return False
    if t.startswith("@") or t.startswith("#"):
        return True
    low = t.lower()
    if any(k in low for k in (
        "likes", "like video", "comments", "followers", "favorites", "added to",
        "shares", "share video", "views", "unread", "contains:", "sound ",
        "inactive", "deleted", "suggested", "something went wrong", "no ",
    )):
        return True
    return False


def _dedup(items, keyf):
    seen, out = set(), []
    for it in items:
        k = keyf(it)
        if k in seen:
            continue
        seen.add(k)
        out.append(it)
    return out


def recognize(elements, threshold: int = 3):
    """识别当前页面 + 分类控件。返回 dict。"""
    onscreen = [e for e in elements if _in_screen(e.get("y"))]
    accs = {e.get("acc_id") for e in onscreen if e.get("acc_id")}
    clses = {e.get("class", "") for e in onscreen if e.get("class")}

    def hit(a):
        return a in accs or a in clses

    scores = {page: sum(w for a, w in sig.items() if hit(a))
              for page, sig in PAGE_SIGNATURES.items()}
    best = max(scores, key=scores.get)
    hits = [(a, w) for a, w in PAGE_SIGNATURES[best].items() if hit(a)]
    total = sum(w for _, w in hits)

    if total >= threshold:
        page = best
        evidence = [f"命中锚点 {a}（权重{w}）" for a, w in sorted(hits, key=lambda x: -x[1])]
    else:
        page = "other"
        evidence = [f"锚点命中不足（{total}/{threshold}）→ 无法确定页面"]

    fixed, vars_ = [], []
    for e in onscreen:
        cls = e.get("class", "")
        acc = e.get("acc_id", "")
        label = (e.get("label") or "").strip()
        item = {
            "cls": cls, "acc": acc, "label": label,
            "x": _num(e.get("x")), "y": _num(e.get("y")),
        }
        if _is_fixed(acc, cls, label):
            fixed.append(item)
        elif _is_var(label):
            vars_.append(item)

    # 去重：固定控件按 (acc|类名+位置分块)，变量按 (类名+内容)
    fixed = _dedup(fixed, lambda i: (i["acc"] or i["cls"], round(i["x"] / 20), round(i["y"] / 40)))
    vars_ = _dedup(vars_, lambda i: (i["cls"], i["label"]))
    fixed.sort(key=lambda i: i["y"])
    vars_.sort(key=lambda i: i["y"])

    return {
        "page": page,
        "title": PAGE_TITLES.get(page, "未知页面"),
        "score": total,
        "threshold": threshold,
        "evidence": evidence,
        "fixed": fixed,
        "vars": vars_,
        "onscreen_count": len(onscreen),
    }
