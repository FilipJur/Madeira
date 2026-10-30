// VLTouch: S1 sink. Accumulates the widget pad state; updateFinished: publishes
// one GamepadSample to VLSink per call (main thread), per
// docs/fork/TOUCH-PORT.md "Sink contract". The ported widgets keep calling
// Moonlight names; only these bodies change.

#import "ControllerSupport.h"
#import "VoidController.h"
#import "VLLiShim.h"
#import "Madeira-Swift.h" // VLSink
#import <UIKit/UIKit.h>

@implementation ControllerSupport {
    int _buttonFlags;
    unsigned char _leftTrigger;
    unsigned char _rightTrigger;
    short _leftStickX;
    short _leftStickY;
    short _rightStickX;
    short _rightStickY;
}

- (instancetype)initWithConfig:(StreamConfiguration *)streamConfig {
    self = [super init];
    if (self) {
        _buttonFlags = 0;
        _leftTrigger = 0;
        _rightTrigger = 0;
        _leftStickX = 0;
        _leftStickY = 0;
        _rightStickX = 0;
        _rightStickY = 0;
    }
    return self;
}

- (void)updateLeftStick:(VoidController *)controller x:(short)x y:(short)y {
    _leftStickX = x;
    _leftStickY = y;
}

- (void)updateRightStick:(VoidController *)controller x:(short)x y:(short)y {
    _rightStickX = x;
    _rightStickY = y;
}

- (void)updateLeftTrigger:(VoidController *)controller left:(unsigned char)left {
    _leftTrigger = left;
}

- (void)updateRightTrigger:(VoidController *)controller right:(unsigned char)right {
    _rightTrigger = right;
}

- (void)setButtonFlag:(VoidController *)controller flags:(int)flags {
    _buttonFlags |= flags;
}

- (void)clearButtonFlag:(VoidController *)controller flags:(int)flags {
    _buttonFlags &= ~flags;
}

// GamepadInput.touch is main-actor; updateFinished: may arrive from the widget
// timers on a background queue, so hop to main before publishing. Snapshot the
// accumulated state into locals first: main must never read ivars a
// background widget thread is still writing.
- (void)updateFinished:(VoidController *)controller {
    int buttons = _buttonFlags;
    unsigned char leftTrigger = _leftTrigger;
    unsigned char rightTrigger = _rightTrigger;
    short leftX = _leftStickX;
    short leftY = _leftStickY;
    short rightX = _rightStickX;
    short rightY = _rightStickY;
    void (^publish)(void) = ^{
        [VLSink publishWithButtons:buttons
                       leftTrigger:leftTrigger
                      rightTrigger:rightTrigger
                             leftX:leftX
                             leftY:leftY
                            rightX:rightX
                            rightY:rightY];
    };
    if ([NSThread isMainThread]) {
        publish();
    } else {
        dispatch_async(dispatch_get_main_queue(), publish);
    }
}

// VoidLink drove gyro/motion timers and physical-pad merging from here
// (ControllerSupport.m updateTimerStateForController:, ~2.3k LOC dropped in
// this port). The VLTouch host (S2) feeds only widget state through this
// facade, so there is nothing to re-arm: motion reaches the guest via the
// stick/mouse rows of the Sink contract (MotionHandler posts through the
// same VLLiShim Li* functions), and DS4 touch / controller motion stay
// no-ops in wave 1 (see VLLiShim.m).
- (void)updateTimerStateForOsc {
}

// OnScreenControls stores this pointer and forwards it back to every call
// above, never dereferencing it (verified: no `[_controller …]` or
// `_controller.` message in OnScreenControls.m; the only use is
// `initWithView:` line 229 storing `[controllerSupport getOscController]`).
// VoidLink's VoidController.m is not in this port (Compat/VoidController.h is
// an S5-owned stub with no @implementation), so allocating one would fail to
// link: return nil, exactly like the P2 facade did.
- (VoidController *)getOscController {
    return nil;
}

@end
