# TikTok Feed 首页（For You）控件全量清单

> 来源：ui_scan 实时扫描（设备 iphone_780EF63F，TikTok 43.7.0 BH）
> 屏幕 414x844。y>0 向下；y<0 = 屏外上方(上一个视频)；y>736 = 屏外下方(下一个视频)。

**共 103 个控件**

## 1. 底部 Tab 栏（y≈712）

| 控件 | acc_id | 位置(x,y) | frame | label | sel |
|---|---|---|---|---|---|
| TTKTabBarButton | a11y_vo_home | (41,712) | {0, 687},{82.799999999999997, 49} | Home | False |
| TTKTabBarAnimationContentView |  | (41,712) | {0, 687},{82.799999999999997, 49} | Home | None |
| TTKTabBarButton | friends | (124,712) | {82.799999999999983, 687},{82.799999999999983, 49} | Friends | False |
| TTKTabBarAnimationContentView |  | (124,712) | {82.799999999999983, 687},{82.799999999999983, 49} | Friends | None |
| UIView |  | (163,683) | {12, 683},{302, 0} |  | None |
| AWEFeedPlayerBottomProgressBar |  | (207,686) | {12, 685},{390, 2} | progressSlider | False |
| AWEFeedPlayerBottomProgressBar |  | (207,686) | {12, 685},{390, 2} | progressSlider | False |
| AWETabBarPlusButton |  | (207,712) | {165.59999999999999, 687},{82.799999999999983, 49} | Create | False |
| TTKTabBarButton | a11y_vo_inbox | (290,712) | {248.39999999999995, 687},{82.799999999999983, 49} | Inbox Button. 0 unread notifications. | False |
| TTKTabBarAnimationContentView |  | (290,712) | {248.39999999999995, 687},{82.799999999999983, 49} | Inbox | None |
| TTKTabBarButton | a11y_vo_profile | (373,712) | {331.19999999999999, 687},{82.800000000000011, 49} | Profile | False |
| TTKTabBarAnimationContentView |  | (373,712) | {331.19999999999999, 687},{82.800000000000011, 49} | Profile | None |
## 2. 顶部 Feed 标签栏（y≈42）

| 控件 | acc_id | 位置(x,y) | frame | label | sel |
|---|---|---|---|---|---|
| TTKFeedTabCornerItemView |  | (28,42) | {8, 22},{40, 40} |  | None |
| AWELiveFeedEntranceView |  | (28,42) | {16, 30},{24, 24} | LIVE | None |
| TikTokFeedTabItemControl | stemFeed_feedScreen_feedName | (62,42) | {35, 20},{53, 44} | STEM | False |
| TikTokFeedTabItemNearbyControl | nearby_tab_name | (120,42) | {88, 20},{64, 44} | Nearby | False |
| HDRUIButton |  | (139,42) | {133, 36},{12, 12} |  | False |
| TikTokFeedTabItemControl | exploretab_tabname_explore | (185,42) | {152, 20},{66, 44} | Explore | False |
| TikTokFeedFadeScrollView |  | (207,42) | {48, 20},{318, 44} |  | None |
| TikTokFeedTabItemFollowControl | following | (259,42) | {218, 20},{81, 44} | Following | False |
| TikTokFeedTabItemControl | top_tabs_recomend | (332,42) | {299, 20},{65, 44} | For You | True |
| TTKMultiTabNavigationArrowView |  | (346,42) | {326, 22.333333333333329},{40, 40} |  | None |
| TTKFeedTabCornerItemView |  | (386,42) | {366, 22},{40, 40} |  | None |
| TTKSearchEntranceButton |  | (386,42) | {374, 30},{24, 24} | Search | False |
| UIButton |  | (389,85) | {374, 70},{30, 30} |  | False |
## 3. 右侧操作栏（屏幕内 y-100~700, x>330）

| 控件 | acc_id | 位置(x,y) | frame | label | sel |
|---|---|---|---|---|---|
| TUXButton |  | (347,8) | {307, -6},{79, 28} | Go LIVE | False |
| UIImageView |  | (386,16) | {376, 6},{20, 20} |  | None |
| TikTokFeedTabItemControl | top_tabs_recomend | (332,42) | {299, 20},{65, 44} | For You | True |
| TTKMultiTabNavigationArrowView |  | (346,42) | {326, 22.333333333333329},{40, 40} |  | None |
| TTKFeedTabCornerItemView |  | (386,42) | {366, 22},{40, 40} |  | None |
| TTKSearchEntranceButton |  | (386,42) | {374, 30},{24, 24} | Search | False |
| UIButton |  | (389,85) | {374, 70},{30, 30} |  | False |
| UIButton |  | (389,125) | {374, 110},{30, 30} |  | False |
| AWEStoryAvatarButton |  | (384,311) | {361.66666666666674, 289},{44, 44} | @lesv3typeshi | False |
| GBLAvatarLiveMarkView |  | (384,311) | {359, 286.66666666666652},{49, 48.666666666666686} | liveMarkView | None |
| UIView |  | (404,332) | {404.33333333333348, 332},{0, 0} | Create a Story | None |
| UIView |  | (404,332) | {404.33333333333348, 332},{0, 0} | Goliath the great is inactive or has deleted their account | None |
| AWEPlayInteractionFollowPromptView |  | (384,333) | {353.66666666666674, 313},{60, 40} | Follow lesv3typeshi | None |
| UIView |  | (384,333) | {353.66666666666674, 313},{60, 40} |  | None |
| UIImageView |  | (384,335) | {373.66666666666674, 325},{20, 20} |  | None |
| AWEFeedVideoButton | feedLikeButton | (382,390) | {357, 366},{49, 48} | Like video. two hundred nine thousand four hundred thirty-eight likes | False |
| AWEFeedVideoButton | feedCommentButton | (371,456) | {336, 432},{70, 48} | Read or add comments. three hundred twelve comments | False |
| AWEFeedVideoButton | feedFavoriteButton | (382,522) | {357, 498},{49, 48} | Add to Favorites. twelve thousand seven hundred fifty-three added to Favorites | False |
| AWEFeedVideoButton | feedShareButton | (371,588) | {336, 564},{70, 48} | Share video. fifty-five thousand six hundred ninety-seven shares | False |
| AWEMusicCoverButton |  | (384,653) | {363.66666666666674, 633},{40, 40} | Sound Lullaby for Babies (Sleep Music for Babies) | False |
## 4. 作者信息/内容区（屏幕内 x<330）

| 控件 | acc_id | 位置(x,y) | frame | label | sel |
|---|---|---|---|---|---|
| TikTokFeedFadeScrollView |  | (207,42) | {48, 20},{318, 44} |  | None |
| TikTokFeedTabItemControl | stemFeed_feedScreen_feedName | (62,42) | {35, 20},{53, 44} | STEM | False |
| TikTokFeedTabItemNearbyControl | nearby_tab_name | (120,42) | {88, 20},{64, 44} | Nearby | False |
| HDRUIButton |  | (139,42) | {133, 36},{12, 12} |  | False |
| TikTokFeedTabItemControl | exploretab_tabname_explore | (185,42) | {152, 20},{66, 44} | Explore | False |
| TikTokFeedTabItemFollowControl | following | (259,42) | {218, 20},{81, 44} | Following | False |
| TTKFeedTabCornerItemView |  | (28,42) | {8, 22},{40, 40} |  | None |
| AWELiveFeedEntranceView |  | (28,42) | {16, 30},{24, 24} | LIVE | None |
| UILabel |  | (207,112) | {32, 112},{350, 0} |  | None |
| AWEPublishProgressDefaultWrapper |  | (35,114) | {12, 84},{45, 60} |  | None |
| TTKCViewComponentPassthroughView | TTKSleepHoursViewComponent | (207,344) | {0, 0},{414, 687} |  | None |
| TTKUpvoteNewBubbleElement |  | (163,610) | {12, 595.66666666666652},{302, 28} |  | None |
| TTKUpvoteBubbleElementWhiteGuideView |  | (88,610) | {12, 595.66666666666652},{152.33333333333334, 28} |  | None |
| AWEPlayInteractionAuthorUserNameButton |  | (75,643) | {12, 631.66666666666652},{126, 23.333333333333371} | Goliath the great | False |
| UIScrollView |  | (163,668) | {12, 653},{302, 30} |  | None |
| AWEPlayInteractionDescriptionLabel |  | (163,668) | {12, 659},{302, 18} | #kitty #cat #kittycat #meow  | None |
| AWEFeedPlayerBottomProgressBar |  | (207,686) | {12, 685},{390, 2} | progressSlider | False |
| AWEFeedPlayerBottomProgressBar |  | (207,686) | {12, 685},{390, 2} | progressSlider | False |
## 5. 屏外预加载 cell（上一个视频 y<0）

| 控件 | acc_id | 位置(x,y) | frame | label | sel |
|---|---|---|---|---|---|
| UIButton |  | (389,-1387) | {374, -1402},{30, 30} |  | False |
| UIButton |  | (389,-1347) | {374, -1362},{30, 30} |  | False |
| AWEStoryAvatarButton |  | (384,-1161) | {361.66666666666674, -1183},{44, 44} | @balleronibolonga | False |
| GBLAvatarLiveMarkView |  | (384,-1161) | {359, -1185.3333333333333},{49, 48.666666666666742} | liveMarkView | None |
| AWEPlayInteractionFollowPromptView |  | (384,-1139) | {353.66666666666674, -1159},{60, 40} | Follow balleronibolonga | None |
| UIImageView |  | (384,-1137) | {373.66666666666674, -1147},{20, 20} |  | None |
| AWEFeedVideoButton | feedLikeButton | (382,-1082) | {357, -1106},{49, 48} | Like video. three million eight hundred ninety-four thousand forty-six likes | False |
| AWEFeedVideoButton | feedCommentButton | (371,-1016) | {336, -1040},{70, 48} | Read or add comments. forty-eight thousand one hundred fifty-one comments | False |
| AWEFeedVideoButton | feedFavoriteButton | (382,-950) | {357, -974},{49, 48} | Add to Favorites. two hundred eighty-seven thousand forty-nine added to Favorites | False |
| AWEFeedVideoButton | feedShareButton | (371,-884) | {336, -908},{70, 48} | Share video. one million two hundred twenty-two thousand eighty-three shares | False |
| AWEPlayInteractionAuthorUserNameButton |  | (75,-853) | {12, -864.33333333333348},{126, 23.333333333333371} | balleronibolonga | False |
| UIScrollView |  | (163,-828) | {12, -843},{302, 30} |  | None |
| AWEPlayInteractionDescriptionLabel |  | (163,-828) | {12, -837},{302, 18} | follow for full tutorials! #howto #fridge  | None |
| AWEMusicCoverButton |  | (384,-819) | {363.66666666666674, -839},{40, 40} | Sound original sound - osman.uysal | False |
| TTKMusicTagView |  | (12,-813) | {12, -813},{0, 0} |  | None |
| TTKMusicTagView |  | (12,-813) | {12, -813},{0, 0} |  | None |
| TTKFeedAddSongToPlaylistTagView |  | (12,-813) | {12, -813},{0, 0} |  | None |
| TTKFeedPresaveTagView |  | (12,-813) | {12, -813},{0, 0} |  | None |
| UIButton |  | (12,-813) | {12, -813},{0, 0} |  | False |
| AWEAwemeMusicInfoView |  | (163,-804) | {12, -813},{302, 18} | Contains: Better Off Alone - Alice DJ | None |
| IESLiveSecurityView |  | (207,-368) | {0, -736},{414, 736} |  | False |
| TTKLivePreviewPageContainerView |  | (207,-368) | {0, -736},{414, 736} |  | None |
## 6. 屏外预加载 cell（下一个视频 y>700）

| 控件 | acc_id | 位置(x,y) | frame | label | sel |
|---|---|---|---|---|---|
| TTKTabBarButton | a11y_vo_home | (41,712) | {0, 687},{82.799999999999997, 49} | Home | False |
| TTKTabBarAnimationContentView |  | (41,712) | {0, 687},{82.799999999999997, 49} | Home | None |
| TTKTabBarButton | friends | (124,712) | {82.799999999999983, 687},{82.799999999999983, 49} | Friends | False |
| TTKTabBarAnimationContentView |  | (124,712) | {82.799999999999983, 687},{82.799999999999983, 49} | Friends | None |
| AWETabBarPlusButton |  | (207,712) | {165.59999999999999, 687},{82.799999999999983, 49} | Create | False |
| TTKTabBarButton | a11y_vo_inbox | (290,712) | {248.39999999999995, 687},{82.799999999999983, 49} | Inbox Button. 0 unread notifications. | False |
| TTKTabBarAnimationContentView |  | (290,712) | {248.39999999999995, 687},{82.799999999999983, 49} | Inbox | None |
| TTKTabBarButton | a11y_vo_profile | (373,712) | {331.19999999999999, 687},{82.800000000000011, 49} | Profile | False |
| TTKTabBarAnimationContentView |  | (373,712) | {331.19999999999999, 687},{82.800000000000011, 49} | Profile | None |
| AWEFeedRefreshFooter |  | (207,5910) | {0, 5888},{414, 44} |   | None |
| UIButton |  | (207,5910) | {0, 5888},{414, 44} |  | False |
| TUXDualBallLoadingIndicator |  | (207,5910) | {191, 5894},{32, 32} | Loading | None |
| YYLabel |  | (207,5910) | {16, 5888},{382, 44} |   | None |
## 7. 其它容器/特殊

| 控件 | acc_id | 位置(x,y) | frame | label | sel |
|---|---|---|---|---|---|
| UIView |  | (404,-1140) | {404.33333333333348, -1140},{0, 0} | Create a Story | None |
| UIView |  | (404,-1140) | {404.33333333333348, -1140},{0, 0} | balleronibolonga is inactive or has deleted their account | None |
| UIView |  | (384,-1139) | {353.66666666666674, -1159},{60, 40} |  | None |
| AWEFeedViewCell |  | (207,-1104) | {0, -1472},{414, 736} | feedcells | None |
| UITableViewCellContentView |  | (207,-1104) | {0, -1472},{414, 736} |  | None |
| TTKFeedInteractionRootView |  | (207,-1104) | {0, -1472},{414, 736} |  | None |
| TTKFeedInteractionPlayerOverlayView |  | (207,-1104) | {0, -1472},{414, 736} |  | None |
| TTKFeedInteractionMainView |  | (207,-1104) | {0, -1472},{414, 736} |  | None |
| TTKStickerContainerView |  | (207,-1104) | {0, -1472},{414, 736} |  | None |
| TTKCommerceAdMaskView |  | (207,-1104) | {0, -1472},{414, 736} |  | None |
| UIView |  | (163,-813) | {12, -813},{302, 0} |  | None |
| UITableViewCellContentView |  | (207,-368) | {0, -736},{414, 736} |  | None |
| UIView |  | (207,19) | {12, 0},{390, 38} |  | None |
| TTKFeedNonPersonalizationTipsView |  | (207,125) | {188, 120},{38, 10} |  | None |
| UIView |  | (404,332) | {404.33333333333348, 332},{0, 0} | Create a Story | None |
| UIView |  | (404,332) | {404.33333333333348, 332},{0, 0} | Goliath the great is inactive or has deleted their account | None |
| UIView |  | (384,333) | {353.66666666666674, 313},{60, 40} |  | None |
| AWEMaskWindow | AWEMaskWindow | (207,368) | {0, 0},{414, 736} |  | None |
| UILayoutContainerView |  | (207,368) | {0, 0},{414, 736} |  | None |
| UIView |  | (207,368) | {0, 0},{414, 736} |  | None |
| AWEFeedSlidingScrollView |  | (207,368) | {0, 0},{414, 736} |  | None |
| UIView | TTKFeedRootComponent | (207,368) | {0, 0},{414, 736} |  | None |
| AWENewFeedTableView | TTKFeedTableViewService | (207,368) | {0, 0},{414, 736} |  | None |
| AWEFeedViewCell |  | (207,368) | {0, 0},{414, 736} | feedcells | None |
| UITableViewCellContentView |  | (207,368) | {0, 0},{414, 736} |  | None |
| TTKFeedInteractionRootView |  | (207,368) | {0, 0},{414, 736} |  | None |
| AWEPlayVideoPlayerControllerBackgroundView |  | (207,368) | {0, 0},{414, 736} |  | None |
| TTKFeedInteractionPlayerOverlayView |  | (207,368) | {0, 0},{414, 736} |  | None |
| TTKFeedInteractionMainView |  | (207,368) | {0, 0},{414, 736} |  | None |
| TTKStickerContainerView |  | (207,368) | {0, 0},{414, 736} |  | None |
| TTKCommerceAdMaskView |  | (207,368) | {0, 0},{414, 736} |  | None |
| TUXSpinner |  | (26,588) | {18, 579.66666666666652},{16, 16} | Loading | None |
| UIView |  | (163,683) | {12, 683},{302, 0} |  | None |
