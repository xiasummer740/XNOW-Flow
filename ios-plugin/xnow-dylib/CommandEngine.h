// CommandEngine.h
// XNOW 指令执行引擎 - 解析并执行后端下发的指令

#import <Foundation/Foundation.h>

typedef void(^CommandCompletion)(NSDictionary *result);

/// 支持的指令类型
typedef NS_ENUM(NSInteger, CommandAction) {
    CommandActionUnknown = 0,
    CommandActionScrollDown,
    CommandActionScrollUp,
    CommandActionLike,
    CommandActionFollow,
    CommandActionComment,
    CommandActionCollect,
    CommandActionScreenshot,
    CommandActionOpenProfile,
    CommandActionCollectFans,
    CommandActionCollectVideos,
    CommandActionBatchLike,
    CommandActionBatchFollow,
    CommandActionBatchComment,
};

@interface CommandEngine : NSObject

/// 执行单条指令
- (void)executeCommand:(NSDictionary *)command completion:(CommandCompletion)completion;

/// 字符串转指令类型
- (CommandAction)actionFromString:(NSString *)actionString;

/// 当前 TikTok 页面类型（未知/推荐/关注/个人/视频详情等）
@property (nonatomic, copy) NSString *currentPage;

@end
