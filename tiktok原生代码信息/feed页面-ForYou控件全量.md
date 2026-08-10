# TikTok Feed 首页（For You） 控件全量清单

> 来源：ui_scan 实时扫描（iPhone 414x844，TikTok 43.7.0 BH）

**共 103 个控件**

## 元素结构树（按 frame 包含关系重建）

```
├─ AWEFeedViewCell (207,-1104) 414x736 "feedcells"
  ├─ UIButton (389,-1387) 30x30
  ├─ UIButton (389,-1347) 30x30
  ├─ GBLAvatarLiveMarkView (384,-1161) 49x48 "liveMarkView"
    ├─ AWEStoryAvatarButton (384,-1161) 44x44 "@balleronibolonga"
  ├─ AWEPlayInteractionFollowPromptView (384,-1139) 60x40 "Follow balleronibolonga"
    ├─ UIImageView (384,-1137) 20x20
  ├─ UIView (384,-1139) 60x40
  ├─ AWEFeedVideoButton (382,-1082) 49x48 acc_id=feedLikeButton "Like video. three million eight hundred ninety-four thousand forty-six likes"
  ├─ AWEFeedVideoButton (371,-1016) 70x48 acc_id=feedCommentButton "Read or add comments. forty-eight thousand one hundred fifty-one comments"
  ├─ AWEFeedVideoButton (382,-950) 49x48 acc_id=feedFavoriteButton "Add to Favorites. two hundred eighty-seven thousand forty-nine added to Favorites"
  ├─ AWEFeedVideoButton (371,-884) 70x48 acc_id=feedShareButton "Share video. one million two hundred twenty-two thousand eighty-three shares"
  ├─ AWEPlayInteractionAuthorUserNameButton (75,-853) 126x23 "balleronibolonga"
  ├─ UIScrollView (163,-828) 302x30
    ├─ AWEPlayInteractionDescriptionLabel (163,-828) 302x18 "follow for full tutorials! #howto #fridge "
  ├─ AWEMusicCoverButton (384,-819) 40x40 "Sound original sound - osman.uysal"
  ├─ AWEAwemeMusicInfoView (163,-804) 302x18 "Contains: Better Off Alone - Alice DJ"
├─ UITableViewCellContentView (207,-1104) 414x736
├─ TTKFeedInteractionRootView (207,-1104) 414x736
├─ TTKFeedInteractionPlayerOverlayView (207,-1104) 414x736
├─ TTKFeedInteractionMainView (207,-1104) 414x736
├─ TTKStickerContainerView (207,-1104) 414x736
├─ TTKCommerceAdMaskView (207,-1104) 414x736
├─ UITableViewCellContentView (207,-368) 414x736
├─ IESLiveSecurityView (207,-368) 414x736
├─ TTKLivePreviewPageContainerView (207,-368) 414x736
├─ TUXButton (347,8) 79x28 "Go LIVE"
├─ AWEMaskWindow (207,368) 414x736 acc_id=AWEMaskWindow
  ├─ TTKCViewComponentPassthroughView (207,344) 414x687 acc_id=TTKSleepHoursViewComponent
    ├─ UIView (207,19) 390x38
      ├─ UIImageView (386,16) 20x20
    ├─ TikTokFeedFadeScrollView (207,42) 318x44
      ├─ TikTokFeedTabItemNearbyControl (120,42) 64x44 acc_id=nearby_tab_name "Nearby"
        ├─ HDRUIButton (139,42) 12x12
      ├─ TikTokFeedTabItemControl (185,42) 66x44 acc_id=exploretab_tabname_explore "Explore"
      ├─ TikTokFeedTabItemFollowControl (259,42) 81x44 acc_id=following "Following"
      ├─ TikTokFeedTabItemControl (332,42) 65x44 acc_id=top_tabs_recomend "For You"
      ├─ TTKMultiTabNavigationArrowView (346,42) 40x40
    ├─ TikTokFeedTabItemControl (62,42) 53x44 acc_id=stemFeed_feedScreen_feedName "STEM"
    ├─ TTKFeedTabCornerItemView (28,42) 40x40
      ├─ AWELiveFeedEntranceView (28,42) 24x24 "LIVE"
    ├─ TTKFeedTabCornerItemView (386,42) 40x40
      ├─ TTKSearchEntranceButton (386,42) 24x24 "Search"
    ├─ UIButton (389,85) 30x30
    ├─ AWEPublishProgressDefaultWrapper (35,114) 45x60
    ├─ UIButton (389,125) 30x30
    ├─ TTKFeedNonPersonalizationTipsView (207,125) 38x10
    ├─ GBLAvatarLiveMarkView (384,311) 49x48 "liveMarkView"
      ├─ AWEStoryAvatarButton (384,311) 44x44 "@lesv3typeshi"
    ├─ AWEPlayInteractionFollowPromptView (384,333) 60x40 "Follow lesv3typeshi"
      ├─ UIImageView (384,335) 20x20
    ├─ UIView (384,333) 60x40
    ├─ AWEFeedVideoButton (382,390) 49x48 acc_id=feedLikeButton "Like video. two hundred nine thousand four hundred thirty-eight likes"
    ├─ AWEFeedVideoButton (371,456) 70x48 acc_id=feedCommentButton "Read or add comments. three hundred twelve comments"
    ├─ AWEFeedVideoButton (382,522) 49x48 acc_id=feedFavoriteButton "Add to Favorites. twelve thousand seven hundred fifty-three added to Favorites"
    ├─ TUXSpinner (26,588) 16x16 "Loading"
    ├─ AWEFeedVideoButton (371,588) 70x48 acc_id=feedShareButton "Share video. fifty-five thousand six hundred ninety-seven shares"
    ├─ TTKUpvoteNewBubbleElement (163,610) 302x28
      ├─ TTKUpvoteBubbleElementWhiteGuideView (88,610) 152x28
    ├─ AWEPlayInteractionAuthorUserNameButton (75,643) 126x23 "Goliath the great"
    ├─ AWEMusicCoverButton (384,653) 40x40 "Sound Lullaby for Babies (Sleep Music for Babies)"
    ├─ UIScrollView (163,668) 302x30
      ├─ AWEPlayInteractionDescriptionLabel (163,668) 302x18 "#kitty #cat #kittycat #meow "
    ├─ AWEFeedPlayerBottomProgressBar (207,686) 390x2 "progressSlider"
    ├─ AWEFeedPlayerBottomProgressBar (207,686) 390x2 "progressSlider"
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
├─ UIView (207,368) 414x736
├─ AWEFeedSlidingScrollView (207,368) 414x736
├─ UIView (207,368) 414x736 acc_id=TTKFeedRootComponent
├─ AWENewFeedTableView (207,368) 414x736 acc_id=TTKFeedTableViewService
├─ AWEFeedViewCell (207,368) 414x736 "feedcells"
├─ UITableViewCellContentView (207,368) 414x736
├─ TTKFeedInteractionRootView (207,368) 414x736
├─ AWEPlayVideoPlayerControllerBackgroundView (207,368) 414x736
├─ TTKFeedInteractionPlayerOverlayView (207,368) 414x736
├─ TTKFeedInteractionMainView (207,368) 414x736
├─ TTKStickerContainerView (207,368) 414x736
├─ TTKCommerceAdMaskView (207,368) 414x736
├─ AWEFeedRefreshFooter (207,5910) 414x44 " "
  ├─ YYLabel (207,5910) 382x44 " "
    ├─ TUXDualBallLoadingIndicator (207,5910) 32x32 "Loading"
├─ UIButton (207,5910) 414x44
```

## 控件全量表格

| # | 控件 | acc_id | 位置(x,y) | frame | label | sel |
|---|---|---|---|---|---|---|
| 1 | UIButton |  | (389,-1387) | {374,-1402},{30,30} |  | False |
| 2 | UIButton |  | (389,-1347) | {374,-1362},{30,30} |  | False |
| 3 | AWEStoryAvatarButton |  | (384,-1161) | {361,-1183},{44,44} | @balleronibolonga | False |
| 4 | GBLAvatarLiveMarkView |  | (384,-1161) | {359,-1185},{49,48} | liveMarkView | None |
| 5 | UIView |  | (404,-1140) | {404,-1140},{0,0} | Create a Story | None |
| 6 | UIView |  | (404,-1140) | {404,-1140},{0,0} | balleronibolonga is inactive or has deleted their account | None |
| 7 | AWEPlayInteractionFollowPromptView |  | (384,-1139) | {353,-1159},{60,40} | Follow balleronibolonga | None |
| 8 | UIView |  | (384,-1139) | {353,-1159},{60,40} |  | None |
| 9 | UIImageView |  | (384,-1137) | {373,-1147},{20,20} |  | None |
| 10 | AWEFeedViewCell |  | (207,-1104) | {0,-1472},{414,736} | feedcells | None |
| 11 | UITableViewCellContentView |  | (207,-1104) | {0,-1472},{414,736} |  | None |
| 12 | TTKFeedInteractionRootView |  | (207,-1104) | {0,-1472},{414,736} |  | None |
| 13 | TTKFeedInteractionPlayerOverlayView |  | (207,-1104) | {0,-1472},{414,736} |  | None |
| 14 | TTKFeedInteractionMainView |  | (207,-1104) | {0,-1472},{414,736} |  | None |
| 15 | TTKStickerContainerView |  | (207,-1104) | {0,-1472},{414,736} |  | None |
| 16 | TTKCommerceAdMaskView |  | (207,-1104) | {0,-1472},{414,736} |  | None |
| 17 | AWEFeedVideoButton | feedLikeButton | (382,-1082) | {357,-1106},{49,48} | Like video. three million eight hundred ninety-four thousand forty-six likes | False |
| 18 | AWEFeedVideoButton | feedCommentButton | (371,-1016) | {336,-1040},{70,48} | Read or add comments. forty-eight thousand one hundred fifty-one comments | False |
| 19 | AWEFeedVideoButton | feedFavoriteButton | (382,-950) | {357,-974},{49,48} | Add to Favorites. two hundred eighty-seven thousand forty-nine added to Favorites | False |
| 20 | AWEFeedVideoButton | feedShareButton | (371,-884) | {336,-908},{70,48} | Share video. one million two hundred twenty-two thousand eighty-three shares | False |
| 21 | AWEPlayInteractionAuthorUserNameButton |  | (75,-853) | {12,-864},{126,23} | balleronibolonga | False |
| 22 | UIScrollView |  | (163,-828) | {12,-843},{302,30} |  | None |
| 23 | AWEPlayInteractionDescriptionLabel |  | (163,-828) | {12,-837},{302,18} | follow for full tutorials! #howto #fridge  | None |
| 24 | AWEMusicCoverButton |  | (384,-819) | {363,-839},{40,40} | Sound original sound - osman.uysal | False |
| 25 | UIView |  | (163,-813) | {12,-813},{302,0} |  | None |
| 26 | TTKMusicTagView |  | (12,-813) | {12,-813},{0,0} |  | None |
| 27 | TTKMusicTagView |  | (12,-813) | {12,-813},{0,0} |  | None |
| 28 | TTKFeedAddSongToPlaylistTagView |  | (12,-813) | {12,-813},{0,0} |  | None |
| 29 | TTKFeedPresaveTagView |  | (12,-813) | {12,-813},{0,0} |  | None |
| 30 | UIButton |  | (12,-813) | {12,-813},{0,0} |  | False |
| 31 | AWEAwemeMusicInfoView |  | (163,-804) | {12,-813},{302,18} | Contains: Better Off Alone - Alice DJ | None |
| 32 | UITableViewCellContentView |  | (207,-368) | {0,-736},{414,736} |  | None |
| 33 | IESLiveSecurityView |  | (207,-368) | {0,-736},{414,736} |  | False |
| 34 | TTKLivePreviewPageContainerView |  | (207,-368) | {0,-736},{414,736} |  | None |
| 35 | TUXButton |  | (347,8) | {307,-6},{79,28} | Go LIVE | False |
| 36 | UIImageView |  | (386,16) | {376,6},{20,20} |  | None |
| 37 | UIView |  | (207,19) | {12,0},{390,38} |  | None |
| 38 | TikTokFeedFadeScrollView |  | (207,42) | {48,20},{318,44} |  | None |
| 39 | TikTokFeedTabItemControl | stemFeed_feedScreen_feedName | (62,42) | {35,20},{53,44} | STEM | False |
| 40 | TikTokFeedTabItemNearbyControl | nearby_tab_name | (120,42) | {88,20},{64,44} | Nearby | False |
| 41 | HDRUIButton |  | (139,42) | {133,36},{12,12} |  | False |
| 42 | TikTokFeedTabItemControl | exploretab_tabname_explore | (185,42) | {152,20},{66,44} | Explore | False |
| 43 | TikTokFeedTabItemFollowControl | following | (259,42) | {218,20},{81,44} | Following | False |
| 44 | TikTokFeedTabItemControl | top_tabs_recomend | (332,42) | {299,20},{65,44} | For You | True |
| 45 | TTKMultiTabNavigationArrowView |  | (346,42) | {326,22},{40,40} |  | None |
| 46 | TTKFeedTabCornerItemView |  | (28,42) | {8,22},{40,40} |  | None |
| 47 | AWELiveFeedEntranceView |  | (28,42) | {16,30},{24,24} | LIVE | None |
| 48 | TTKFeedTabCornerItemView |  | (386,42) | {366,22},{40,40} |  | None |
| 49 | TTKSearchEntranceButton |  | (386,42) | {374,30},{24,24} | Search | False |
| 50 | UIButton |  | (389,85) | {374,70},{30,30} |  | False |
| 51 | UILabel |  | (207,112) | {32,112},{350,0} |  | None |
| 52 | AWEPublishProgressDefaultWrapper |  | (35,114) | {12,84},{45,60} |  | None |
| 53 | UIButton |  | (389,125) | {374,110},{30,30} |  | False |
| 54 | TTKFeedNonPersonalizationTipsView |  | (207,125) | {188,120},{38,10} |  | None |
| 55 | AWEStoryAvatarButton |  | (384,311) | {361,289},{44,44} | @lesv3typeshi | False |
| 56 | GBLAvatarLiveMarkView |  | (384,311) | {359,286},{49,48} | liveMarkView | None |
| 57 | UIView |  | (404,332) | {404,332},{0,0} | Create a Story | None |
| 58 | UIView |  | (404,332) | {404,332},{0,0} | Goliath the great is inactive or has deleted their account | None |
| 59 | AWEPlayInteractionFollowPromptView |  | (384,333) | {353,313},{60,40} | Follow lesv3typeshi | None |
| 60 | UIView |  | (384,333) | {353,313},{60,40} |  | None |
| 61 | UIImageView |  | (384,335) | {373,325},{20,20} |  | None |
| 62 | TTKCViewComponentPassthroughView | TTKSleepHoursViewComponent | (207,344) | {0,0},{414,687} |  | None |
| 63 | AWEMaskWindow | AWEMaskWindow | (207,368) | {0,0},{414,736} |  | None |
| 64 | UILayoutContainerView |  | (207,368) | {0,0},{414,736} |  | None |
| 65 | UIView |  | (207,368) | {0,0},{414,736} |  | None |
| 66 | AWEFeedSlidingScrollView |  | (207,368) | {0,0},{414,736} |  | None |
| 67 | UIView | TTKFeedRootComponent | (207,368) | {0,0},{414,736} |  | None |
| 68 | AWENewFeedTableView | TTKFeedTableViewService | (207,368) | {0,0},{414,736} |  | None |
| 69 | AWEFeedViewCell |  | (207,368) | {0,0},{414,736} | feedcells | None |
| 70 | UITableViewCellContentView |  | (207,368) | {0,0},{414,736} |  | None |
| 71 | TTKFeedInteractionRootView |  | (207,368) | {0,0},{414,736} |  | None |
| 72 | AWEPlayVideoPlayerControllerBackgroundView |  | (207,368) | {0,0},{414,736} |  | None |
| 73 | TTKFeedInteractionPlayerOverlayView |  | (207,368) | {0,0},{414,736} |  | None |
| 74 | TTKFeedInteractionMainView |  | (207,368) | {0,0},{414,736} |  | None |
| 75 | TTKStickerContainerView |  | (207,368) | {0,0},{414,736} |  | None |
| 76 | TTKCommerceAdMaskView |  | (207,368) | {0,0},{414,736} |  | None |
| 77 | AWEFeedVideoButton | feedLikeButton | (382,390) | {357,366},{49,48} | Like video. two hundred nine thousand four hundred thirty-eight likes | False |
| 78 | AWEFeedVideoButton | feedCommentButton | (371,456) | {336,432},{70,48} | Read or add comments. three hundred twelve comments | False |
| 79 | AWEFeedVideoButton | feedFavoriteButton | (382,522) | {357,498},{49,48} | Add to Favorites. twelve thousand seven hundred fifty-three added to Favorites | False |
| 80 | TUXSpinner |  | (26,588) | {18,579},{16,16} | Loading | None |
| 81 | AWEFeedVideoButton | feedShareButton | (371,588) | {336,564},{70,48} | Share video. fifty-five thousand six hundred ninety-seven shares | False |
| 82 | TTKUpvoteNewBubbleElement |  | (163,610) | {12,595},{302,28} |  | None |
| 83 | TTKUpvoteBubbleElementWhiteGuideView |  | (88,610) | {12,595},{152,28} |  | None |
| 84 | AWEPlayInteractionAuthorUserNameButton |  | (75,643) | {12,631},{126,23} | Goliath the great | False |
| 85 | AWEMusicCoverButton |  | (384,653) | {363,633},{40,40} | Sound Lullaby for Babies (Sleep Music for Babies) | False |
| 86 | UIScrollView |  | (163,668) | {12,653},{302,30} |  | None |
| 87 | AWEPlayInteractionDescriptionLabel |  | (163,668) | {12,659},{302,18} | #kitty #cat #kittycat #meow  | None |
| 88 | UIView |  | (163,683) | {12,683},{302,0} |  | None |
| 89 | AWEFeedPlayerBottomProgressBar |  | (207,686) | {12,685},{390,2} | progressSlider | False |
| 90 | AWEFeedPlayerBottomProgressBar |  | (207,686) | {12,685},{390,2} | progressSlider | False |
| 91 | TTKTabBarButton | a11y_vo_home | (41,712) | {0,687},{82,49} | Home | False |
| 92 | TTKTabBarAnimationContentView |  | (41,712) | {0,687},{82,49} | Home | None |
| 93 | TTKTabBarButton | friends | (124,712) | {82,687},{82,49} | Friends | False |
| 94 | TTKTabBarAnimationContentView |  | (124,712) | {82,687},{82,49} | Friends | None |
| 95 | AWETabBarPlusButton |  | (207,712) | {165,687},{82,49} | Create | False |
| 96 | TTKTabBarButton | a11y_vo_inbox | (290,712) | {248,687},{82,49} | Inbox Button. 0 unread notifications. | False |
| 97 | TTKTabBarAnimationContentView |  | (290,712) | {248,687},{82,49} | Inbox | None |
| 98 | TTKTabBarButton | a11y_vo_profile | (373,712) | {331,687},{82,49} | Profile | False |
| 99 | TTKTabBarAnimationContentView |  | (373,712) | {331,687},{82,49} | Profile | None |
| 100 | AWEFeedRefreshFooter |  | (207,5910) | {0,5888},{414,44} |   | None |
| 101 | UIButton |  | (207,5910) | {0,5888},{414,44} |  | False |
| 102 | TUXDualBallLoadingIndicator |  | (207,5910) | {191,5894},{32,32} | Loading | None |
| 103 | YYLabel |  | (207,5910) | {16,5888},{382,44} |   | None |
