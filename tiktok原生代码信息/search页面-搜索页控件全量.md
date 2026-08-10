# TikTok 搜索页（Search） 控件全量清单

> 来源：ui_scan 实时扫描（iPhone 414x844，TikTok 43.7.0 BH）

**共 29 个控件**

## 元素结构树（按 frame 包含关系重建）

```
├─ AWEMaskWindow (207,368) 414x736 acc_id=AWEMaskWindow
  ├─ UIButton (26,42) 44x44 "Back"
  ├─ TTKSearchPressStatusButton (374,42) 49x31 "Search"
  ├─ AWESearchBar (191,42) 285x36
    ├─ _UISearchBarFieldEditor (206,42) 254x36
      ├─ TTKSearchBarRightButton (309,42) 48x36 "Voice search"
        ├─ UIView (315,42) 36x36
  ├─ _UISearchBarSearchContainerView (191,42) 285x36
  ├─ UISearchBarTextField (191,42) 285x36
├─ UILayoutContainerView (207,368) 414x736
├─ UITableView (207,414) 414x700
  ├─ UIView (207,400) 414x672
    ├─ LynxScrollView (207,290) 414x452
      ├─ LynxTextView (374,98) 47x17 "Refresh"
      ├─ AWEPublishProgressDefaultWrapper (35,114) 45x60
      ├─ LynxTextView (207,302) 185x24 "Something went wrong"
      ├─ LynxTextView (207,332) 242x21 "No suggested search topics available."
    ├─ TTKTabBarButton (41,712) 82x49 acc_id=a11y_vo_home "Home"
    ├─ TTKTabBarAnimationContentView (41,712) 82x49 "Home"
    ├─ TTKTabBarButton (124,712) 82x49 acc_id=friends "Friends"
    ├─ TTKTabBarAnimationContentView (124,712) 82x49 "Friends"
    ├─ AWETabBarPlusButton (207,712) 82x49 "Create"
    ├─ TTKTabBarButton (290,712) 82x49 acc_id=a11y_vo_inbox "Inbox Button. 0 unread notifications."
    ├─ TTKTabBarAnimationContentView (290,712) 82x49 "Inbox"
    ├─ TTKTabBarButton (373,712) 82x49 acc_id=a11y_vo_profile "Profile"
    ├─ TTKTabBarAnimationContentView (373,712) 82x49 "Profile"
  ├─ UITableView (207,400) 414x672
├─ UITableViewCellContentView (207,414) 414x700
├─ HybridLynxView (207,414) 414x700 "lynxview"
```

## 控件全量表格

| # | 控件 | acc_id | 位置(x,y) | frame | label | sel |
|---|---|---|---|---|---|---|
| 1 | UIButton |  | (26,42) | {4,20},{44,44} | Back | False |
| 2 | TTKSearchPressStatusButton |  | (374,42) | {349,26},{49,31} | Search | False |
| 3 | AWESearchBar |  | (191,42) | {48,24},{285,36} |  | None |
| 4 | _UISearchBarSearchContainerView |  | (191,42) | {48,24},{285,36} |  | None |
| 5 | UISearchBarTextField |  | (191,42) | {48,24},{285,36} |  | False |
| 6 | _UISearchBarFieldEditor |  | (206,42) | {79,24},{254,36} |  | None |
| 7 | TTKSearchBarRightButton |  | (309,42) | {285,24},{48,36} | Voice search | None |
| 8 | UIView |  | (315,42) | {297,24},{36,36} |  | None |
| 9 | LynxTextView |  | (374,98) | {350,89},{47,17} | Refresh | None |
| 10 | AWEPublishProgressDefaultWrapper |  | (35,114) | {12,84},{45,60} |  | None |
| 11 | LynxScrollView |  | (207,290) | {0,64},{414,452} |  | None |
| 12 | LynxTextView |  | (207,302) | {114,289},{185,24} | Something went wrong | None |
| 13 | LynxTextView |  | (207,332) | {85,321},{242,21} | No suggested search topics available. | None |
| 14 | AWEMaskWindow | AWEMaskWindow | (207,368) | {0,0},{414,736} |  | None |
| 15 | UILayoutContainerView |  | (207,368) | {0,0},{414,736} |  | None |
| 16 | UIView |  | (207,400) | {0,64},{414,672} |  | None |
| 17 | UITableView |  | (207,400) | {0,64},{414,672} |  | None |
| 18 | UITableView |  | (207,414) | {0,64},{414,700} |  | None |
| 19 | UITableViewCellContentView |  | (207,414) | {0,64},{414,700} |  | None |
| 20 | HybridLynxView |  | (207,414) | {0,64},{414,700} | lynxview | None |
| 21 | TTKTabBarButton | a11y_vo_home | (41,712) | {0,687},{82,49} | Home | False |
| 22 | TTKTabBarAnimationContentView |  | (41,712) | {0,687},{82,49} | Home | None |
| 23 | TTKTabBarButton | friends | (124,712) | {82,687},{82,49} | Friends | False |
| 24 | TTKTabBarAnimationContentView |  | (124,712) | {82,687},{82,49} | Friends | None |
| 25 | AWETabBarPlusButton |  | (207,712) | {165,687},{82,49} | Create | False |
| 26 | TTKTabBarButton | a11y_vo_inbox | (290,712) | {248,687},{82,49} | Inbox Button. 0 unread notifications. | False |
| 27 | TTKTabBarAnimationContentView |  | (290,712) | {248,687},{82,49} | Inbox | None |
| 28 | TTKTabBarButton | a11y_vo_profile | (373,712) | {331,687},{82,49} | Profile | False |
| 29 | TTKTabBarAnimationContentView |  | (373,712) | {331,687},{82,49} | Profile | None |
