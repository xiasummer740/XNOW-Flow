// XNTouchSimulator.h
// XNOW 真实触摸模拟 — 用 UITouch/UIEvent 注入真实触摸事件
// 让 TikTok 的 UIGestureRecognizer / UIControl 真正响应（替代旧的 sendActions/空touches）

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface XNTouchSimulator : NSObject

/// 真实模拟一次点击（touchesBegan → touchesEnded）
+ (void)tapAtPoint:(CGPoint)point;

/// 真实模拟一次滑动（touchesBegan → touchesMoved×N → touchesEnded）
+ (void)swipeFrom:(CGPoint)from to:(CGPoint)to;

/// 便捷：手指上滑（TikTok = 下一个视频）
+ (void)swipeUp;

/// 便捷：手指下滑（TikTok = 上一个视频）
+ (void)swipeDown;

@end

NS_ASSUME_NONNULL_END
