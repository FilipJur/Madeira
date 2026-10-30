// VLTouch: facade; S1 wires to GamepadInput.

#import "ControllerSupport.h"

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
    // VLTouch: facade; S1 wires to GamepadInput.
    _leftStickX = x;
    _leftStickY = y;
}

- (void)updateRightStick:(VoidController *)controller x:(short)x y:(short)y {
    // VLTouch: facade; S1 wires to GamepadInput.
    _rightStickX = x;
    _rightStickY = y;
}

- (void)updateLeftTrigger:(VoidController *)controller left:(unsigned char)left {
    // VLTouch: facade; S1 wires to GamepadInput.
    _leftTrigger = left;
}

- (void)updateRightTrigger:(VoidController *)controller right:(unsigned char)right {
    // VLTouch: facade; S1 wires to GamepadInput.
    _rightTrigger = right;
}

- (void)setButtonFlag:(VoidController *)controller flags:(int)flags {
    // VLTouch: facade; S1 wires to GamepadInput.
    _buttonFlags |= flags;
}

- (void)clearButtonFlag:(VoidController *)controller flags:(int)flags {
    // VLTouch: facade; S1 wires to GamepadInput.
    _buttonFlags &= ~flags;
}

- (void)updateFinished:(VoidController *)controller {
    // VLTouch: facade; S1 wires to GamepadInput.
}

- (void)updateTimerStateForOsc {
    // VLTouch: facade; S1 wires to GamepadInput.
}

- (VoidController *)getOscController {
    // VLTouch: facade; S1 wires to GamepadInput.
    return nil;
}

@end
