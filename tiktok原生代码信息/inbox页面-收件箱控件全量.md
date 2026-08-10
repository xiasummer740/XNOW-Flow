# TikTok 收件箱（Inbox） 控件全量清单

> 来源：ui_scan 实时扫描（iPhone 414x844，TikTok 43.7.0 BH）

**共 75 个控件**

## 元素结构树（按 frame 包含关系重建）

```
├─ TUXDualBallLoadingIndicator (207,0) 32x32 "Loading"
├─ AWEMaskWindow (207,368) 414x736 acc_id=AWEMaskWindow
  ├─ TUXBadge (51,20) 10x16 "You have new notifications,0"
  ├─ TUXBadgeCore (51,20) 10x16 "You have new notifications,0"
  ├─ AWESwitchAccountNavigationBarTitleView (207,42) 110x26
    ├─ UIButton (207,41) 72x24 "Add name"
    ├─ UIImageView (251,41) 15x16 "Switch accounts"
  ├─ TTKProfileViewsEntryView (306,42) 40x44 acc_id=nav_bar_end_viewer_entrance "Profile view. 0 profile views."
  ├─ UIButton (346,42) 40x44 acc_id=nav_bar_end_share_profile
  ├─ UIButton (386,42) 40x44 acc_id=nav_bar_end_settings
  ├─ UIButton (28,42) 40x44 acc_id=nav_bar_start_find_friends "Find friends"
  ├─ TTKProfileRootView (207,185) 414x309 acc_id=TTKProfileRootComponent
    ├─ TTKProfileHeaderView (207,165) 414x269 acc_id=header
      ├─ TTKProfileAvatarContainerView (207,96) 414x131 acc_id=header_avatar
        ├─ TTKProfileAvatarSectionView (207,96) 130x131 acc_id=avatar_normal
          ├─ UIView (207,55) 60x40
            ├─ TikTokSocialImplSwift.AlwaysCursorPlaceholderTextView (207,55) 60x37
              ├─ TikTokSocialImplSwift.StoryNoteGradientTextView (185,55) 16x24
          ├─ BDImageView (207,107) 96x96 "Outshine, Profile photo,"
            ├─ TTKAvatarCommonBadgeView (243,143) 24x24
            ├─ UIView (243,143) 24x24 "Plus"
        ├─ AWEPublishProgressDefaultWrapper (35,114) 45x60
      ├─ UIView (207,210) 414x98 acc_id=info
        ├─ UIView (207,187) 414x51 acc_id=user_info
          ├─ UIView (289,177) 58x30 acc_id=user_info_manage
            ├─ UIButton (289,177) 48x28
          ├─ UIView (289,177) 58x30 acc_id=user_info_manage_edit_profile
          ├─ UIView (207,178) 414x23 acc_id=user_account_name_info
            ├─ AWESwitchAccountProfileInfoTitleView (207,178) 95x23 acc_id=user_info_nickname
              ├─ UIImageView (243,177) 16x16 "Switch accounts"
              ├─ UIButton (189,178) 59x23 "Add name"
          ├─ AWEUserNameLabel (207,198) 80x20 acc_id=user_account_user_name "@outshine83"
          ├─ UIView (207,199) 414x19 acc_id=user_account_base_info
        ├─ UIView (207,236) 414x47 acc_id=user_relation_info
          ├─ UIStackView (107,235) 100x36 acc_id=relation_info_following "0, Following,"
          ├─ UIStackView (207,235) 100x36 acc_id=relation_info_follower "0, Followers,"
          ├─ UIStackView (307,235) 100x36 acc_id=relation_info_like "0, Likes,"
      ├─ TTKProfileBIOSectionView (207,277) 414x36 acc_id=bio
        ├─ UIView (207,277) 334x28 acc_id=bio_add_bio
          ├─ UIButton (207,277) 247x28
    ├─ UIView (207,319) 414x40 acc_id=profile_tab
      ├─ TTKProfileTabVideoButton (64,319) 94x40 acc_id=TTKProfileTabVideoButton_0 "Posts"
      ├─ TTKProfileTabBaseButton (159,319) 94x40 acc_id=TTKProfileTabBaseButton_10 "Private"
      ├─ TTKProfileTabFavouriteButton (255,319) 94x40 acc_id=TTKProfileTabFavouriteButton_6 "Favorites"
      ├─ TTKProfileTabLikeButton (350,319) 94x40 acc_id=TTKProfileTabLikeButton_2 "Liked"
    ├─ UIScrollView (207,319) 414x40
  ├─ UIView (207,362) 414x46
    ├─ UIButton (390,362) 16x22 "Close"
  ├─ UIView (207,385) 414x0
  ├─ UIView (207,483) 414x194
    ├─ TUXButton (207,539) 89x32 "Upload"
  ├─ TUXButton (207,587) 89x40 "Upload"
  ├─ UIButton (207,602) 414x44
    ├─ YYLabel (207,602) 382x44 "No more results"
      ├─ TUXDualBallLoadingIndicator (207,602) 32x32 "Loading"
  ├─ TTKTabBarButton (41,712) 82x49 acc_id=a11y_vo_home "Home"
  ├─ TTKTabBarAnimationContentView (41,712) 82x49 "Home"
  ├─ TTKTabBarButton (124,712) 82x49 acc_id=friends "Friends"
  ├─ TTKTabBarAnimationContentView (124,712) 82x49 "Friends"
  ├─ AWETabBarPlusButton (207,712) 82x49 "Create"
  ├─ TTKTabBarButton (290,712) 82x49 acc_id=a11y_vo_inbox "Inbox Button. 0 unread notifications."
  ├─ TTKTabBarAnimationContentView (290,712) 82x49 "Inbox"
  ├─ TTKTabBarButton (373,712) 82x49 acc_id=a11y_vo_profile "Profile"
  ├─ TTKTabBarAnimationContentView (373,712) 82x49 "Profile"
├─ UILayoutContainerView (207,368) 414x736
├─ AWEUserProfileSlidingScrollView (207,368) 414x736
├─ TTKUserProfileWorkCollectionView (207,368) 414x736
```

## 控件全量表格

| # | 控件 | acc_id | 位置(x,y) | frame | label | sel |
|---|---|---|---|---|---|---|
| 1 | TUXDualBallLoadingIndicator |  | (207,0) | {191,-16},{32,32} | Loading | None |
| 2 | TUXBadge |  | (51,20) | {46,12},{10,16} | You have new notifications,0 | None |
| 3 | TUXBadgeCore |  | (51,20) | {46,12},{10,16} | You have new notifications,0 | None |
| 4 | UIButton |  | (207,41) | {170,29},{72,24} | Add name | False |
| 5 | UIImageView |  | (251,41) | {242,33},{15,16} | Switch accounts | None |
| 6 | AWESwitchAccountNavigationBarTitleView |  | (207,42) | {151,29},{110,26} |  | None |
| 7 | TTKProfileViewsEntryView | nav_bar_end_viewer_entrance | (306,42) | {286,20},{40,44} | Profile view. 0 profile views. | None |
| 8 | UIButton | nav_bar_end_share_profile | (346,42) | {326,20},{40,44} |  | False |
| 9 | UIButton | nav_bar_end_settings | (386,42) | {366,20},{40,44} |  | False |
| 10 | UIButton | nav_bar_start_find_friends | (28,42) | {8,20},{40,44} | Find friends | False |
| 11 | UIView |  | (207,55) | {177,35},{60,40} |  | None |
| 12 | TikTokSocialImplSwift.StoryNoteGradientTextView |  | (185,55) | {177,42},{16,24} |  | None |
| 13 | TikTokSocialImplSwift.AlwaysCursorPlaceholderTextView |  | (207,55) | {177,36},{60,37} |  | None |
| 14 | UILabel |  | (207,55) | {155,55},{102,0} |  | None |
| 15 | BDImageView |  | (159,59) | {159,59},{0,0} |  | None |
| 16 | BDImageView |  | (159,59) | {159,59},{0,0} |  | None |
| 17 | BDImageView |  | (159,59) | {159,59},{0,0} |  | None |
| 18 | TTKProfileAvatarContainerView | header_avatar | (207,96) | {0,30},{414,131} |  | None |
| 19 | TTKProfileAvatarSectionView | avatar_normal | (207,96) | {141,30},{130,131} |  | None |
| 20 | BDImageView |  | (207,107) | {159,59},{96,96} | Outshine, Profile photo, | None |
| 21 | AWEPublishProgressDefaultWrapper |  | (35,114) | {12,84},{45,60} |  | None |
| 22 | TTKAvatarCommonBadgeView |  | (243,143) | {231,131},{24,24} |  | None |
| 23 | UIView |  | (243,143) | {231,131},{24,24} | Plus | None |
| 24 | TTKProfileHeaderView | header | (207,165) | {0,30},{414,269} |  | None |
| 25 | UIImageView |  | (243,177) | {234,169},{16,16} | Switch accounts | None |
| 26 | UIView | user_info_manage | (289,177) | {259,162},{58,30} |  | None |
| 27 | UIView | user_info_manage_edit_profile | (289,177) | {259,162},{58,30} |  | None |
| 28 | UIButton |  | (289,177) | {264,163},{48,28} |  | False |
| 29 | UIView | user_account_name_info | (207,178) | {0,166},{414,23} |  | None |
| 30 | AWESwitchAccountProfileInfoTitleView | user_info_nickname | (207,178) | {159,166},{95,23} |  | None |
| 31 | UIButton |  | (189,178) | {159,166},{59,23} | Add name | False |
| 32 | TTKProfileRootView | TTKProfileRootComponent | (207,185) | {0,30},{414,309} |  | None |
| 33 | UIView | user_info | (207,187) | {0,161},{414,51} |  | None |
| 34 | AWEUserNameLabel | user_account_user_name | (207,198) | {166,188},{80,20} | @outshine83 | None |
| 35 | UIView | user_account_base_info | (207,199) | {0,189},{414,19} |  | None |
| 36 | UIView | info | (207,210) | {0,161},{414,98} |  | None |
| 37 | UIStackView | relation_info_following | (107,235) | {57,217},{100,36} | 0, Following, | None |
| 38 | UIStackView | relation_info_follower | (207,235) | {157,217},{100,36} | 0, Followers, | None |
| 39 | UIStackView | relation_info_like | (307,235) | {257,217},{100,36} | 0, Likes, | None |
| 40 | UIView | user_relation_info | (207,236) | {0,212},{414,47} |  | None |
| 41 | TTKProfileRecommendContainerView | recommend | (207,259) | {0,259},{414,0} |  | None |
| 42 | UIView | recommend_user_card | (207,259) | {0,259},{414,0} |  | None |
| 43 | TTKProfileBIOSectionView | bio | (207,277) | {0,259},{414,36} |  | None |
| 44 | UIView | bio_add_bio | (207,277) | {40,263},{334,28} |  | None |
| 45 | UIButton |  | (207,277) | {83,263},{247,28} |  | False |
| 46 | UIView | profile_tab | (207,319) | {0,299},{414,40} |  | None |
| 47 | UIScrollView |  | (207,319) | {0,299},{414,40} |  | None |
| 48 | TTKProfileTabVideoButton | TTKProfileTabVideoButton_0 | (64,319) | {16,299},{94,40} | Posts | True |
| 49 | TTKProfileTabBaseButton | TTKProfileTabBaseButton_10 | (159,319) | {112,299},{94,40} | Private | False |
| 50 | TTKProfileTabFavouriteButton | TTKProfileTabFavouriteButton_6 | (255,319) | {207,299},{94,40} | Favorites | False |
| 51 | TTKProfileTabLikeButton | TTKProfileTabLikeButton_2 | (350,319) | {303,299},{94,40} | Liked | False |
| 52 | TTKCViewComponentPassthroughView | nav_bar | (207,339) | {0,339},{414,0} |  | None |
| 53 | UIView |  | (207,362) | {0,339},{414,46} |  | None |
| 54 | UIButton |  | (390,362) | {382,351},{16,22} | Close | False |
| 55 | AWEMaskWindow | AWEMaskWindow | (207,368) | {0,0},{414,736} |  | None |
| 56 | UILayoutContainerView |  | (207,368) | {0,0},{414,736} |  | None |
| 57 | AWEUserProfileSlidingScrollView |  | (207,368) | {0,0},{414,736} |  | None |
| 58 | TTKUserProfileWorkCollectionView |  | (207,368) | {0,0},{414,736} |  | None |
| 59 | UIView |  | (207,385) | {0,385},{414,0} |  | None |
| 60 | UICollectionView |  | (207,386) | {0,385},{414,0} |  | None |
| 61 | UIView |  | (207,483) | {0,385},{414,194} |  | None |
| 62 | TUXButton |  | (207,539) | {162,523},{89,32} | Upload | False |
| 63 | TUXButton |  | (207,587) | {162,566},{89,40} | Upload | False |
| 64 | UIButton |  | (207,602) | {0,579},{414,44} |  | False |
| 65 | TUXDualBallLoadingIndicator |  | (207,602) | {191,585},{32,32} | Loading | None |
| 66 | YYLabel |  | (207,602) | {16,579},{382,44} | No more results | None |
| 67 | TTKTabBarButton | a11y_vo_home | (41,712) | {0,687},{82,49} | Home | False |
| 68 | TTKTabBarAnimationContentView |  | (41,712) | {0,687},{82,49} | Home | None |
| 69 | TTKTabBarButton | friends | (124,712) | {82,687},{82,49} | Friends | False |
| 70 | TTKTabBarAnimationContentView |  | (124,712) | {82,687},{82,49} | Friends | None |
| 71 | AWETabBarPlusButton |  | (207,712) | {165,687},{82,49} | Create | False |
| 72 | TTKTabBarButton | a11y_vo_inbox | (290,712) | {248,687},{82,49} | Inbox Button. 0 unread notifications. | False |
| 73 | TTKTabBarAnimationContentView |  | (290,712) | {248,687},{82,49} | Inbox | None |
| 74 | TTKTabBarButton | a11y_vo_profile | (373,712) | {331,687},{82,49} | Profile | False |
| 75 | TTKTabBarAnimationContentView |  | (373,712) | {331,687},{82,49} | Profile | None |
