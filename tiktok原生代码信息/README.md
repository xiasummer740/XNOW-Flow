# TikTok 原生代码信息库

> 用途：记录 TikTok 原生 App（43.7.0 BH 版，屏幕 414x844）的真实控件结构，作为 XNOW 插件开发参考。
> 避免反复用 ui_scan 盲试控件，直接查此库。

## 如何获取数据
- 设备在线 → 下发 `ui_scan` 命令 → 后端 server.log 记录每个可交互控件（类名/位置/frame/acc_id/label/选中态）
- 整理成 markdown 存本目录

## 已收录页面（每页含完整元素结构树 + 全量表格）
| 文件 | 页面 | 控件数 |
|---|---|---|
| feed页面-ForYou控件全量.md | Feed 首页（For You） | 103 |
| inbox页面-收件箱控件全量.md | 收件箱（Inbox） | 75 |
| profile页面-个人主页控件全量.md | 个人主页（Profile） | 75 |
| search页面-搜索页控件全量.md | 搜索页（Search） | 29 |

> 每份文档包含：①**元素结构树**（按 frame 包含关系重建的父子层级，缩进显示）②**控件全量表格**（类名/acc_id/位置/frame/label/选中态）

## 关键控件速查（Feed 首页）
| 功能 | 控件 | acc_id | 位置(x,y) | label 示例 |
|---|---|---|---|---|
| 首页 tab | TTKTabBarButton | a11y_vo_home | (41,712) | Home |
| 收件箱 tab | TTKTabBarButton | a11y_vo_inbox | (290,712) | Inbox Button. 0 unread |
| 我的 tab | TTKTabBarButton | a11y_vo_profile | (373,712) | Profile |
| For You 标签 | TikTokFeedTabItemControl | top_tabs_recomend | (332,42) | For You |
| Following 标签 | TikTokFeedTabItemFollowControl | following | (259,42) | Following |
| 搜索 | TTKSearchEntranceButton | (无) | (386,42) | Search |
| 关注按钮 | AWEPlayInteractionFollowPromptView | (无) | (384,333) | Follow 作者名 |
| 点赞 | AWEFeedVideoButton | **feedLikeButton** | (382,390) | Like video. XX likes |
| 评论 | AWEFeedVideoButton | **feedCommentButton** | (371,456) | Read or add comments |
| 收藏 | AWEFeedVideoButton | **feedFavoriteButton** | (382,522) | Add to Favorites |
| 分享 | AWEFeedVideoButton | **feedShareButton** | (371,588) | Share video |
| 作者名 | AWEPlayInteractionAuthorUserNameButton | (无) | (75,643) | 用户名 |
| 视频描述 | AWEPlayInteractionDescriptionLabel | (无) | (163,668) | 话题/描述 |
| 音乐 | AWEMusicCoverButton | (无) | (384,653) | Sound ... |
| 进度条 | AWEFeedPlayerBottomProgressBar | (无) | (207,686) | progressSlider |

> ⚠️ 注意：feed 有多个同名控件（当前视频 + 屏外预加载 cell，y 会差 ±736/±1104）。
> 操作时必须只命中"屏幕内可见"的那个（用 y 在 0~736 过滤）。

## 待补页面
- 评论面板（需专用"打开评论"命令，当前 comment 命令会连带发评论）
- 直播间（需主播开播，`open_live` 才可进入）
- 私信/聊天
