// VLTouch: minimal stand-in for VoidLink's StreamConfiguration; OnScreenControls
// reads the two flags at init (S2's host owns what values to pass).
#import <Foundation/Foundation.h>

@interface StreamConfiguration : NSObject

@property (nonatomic) BOOL swapABXYButtons;
@property (nonatomic) BOOL buttonVisualFeedback;

@end
