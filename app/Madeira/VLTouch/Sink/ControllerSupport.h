// VLTouch: ControllerSupport facade — the nine selectors the ported widgets call; bodies accumulate only.

#import <Foundation/Foundation.h>

@class StreamConfiguration;
@class VoidController;

@interface ControllerSupport : NSObject

// VLTouch: port constructor; VoidLink's delegate: argument belongs to the dropped app model.
- (instancetype)initWithConfig:(StreamConfiguration *)streamConfig;

- (void)updateLeftStick:(VoidController *)controller x:(short)x y:(short)y;
- (void)updateRightStick:(VoidController *)controller x:(short)x y:(short)y;

- (void)updateLeftTrigger:(VoidController *)controller left:(unsigned char)left;
- (void)updateRightTrigger:(VoidController *)controller right:(unsigned char)right;

- (void)setButtonFlag:(VoidController *)controller flags:(int)flags;
- (void)clearButtonFlag:(VoidController *)controller flags:(int)flags;

- (void)updateFinished:(VoidController *)controller;

// VLTouch: zero buttons, triggers and sticks without publishing. The host calls it when it
// discards the OnScreenControls that fed this object, so a later updateFinished: cannot
// republish bits whose touch-up will never arrive.
- (void)resetState;

- (void)updateTimerStateForOsc;

- (VoidController *)getOscController;

@end
