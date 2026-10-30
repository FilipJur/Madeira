// VLTouch: stands in for moonlight-common-c's Limelight.h — prototypes and constants the ported widget code uses.

#ifndef VLLI_SHIM_H
#define VLLI_SHIM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Protocol constants, verbatim from moonlight-common-c src/Limelight.h.
#define KEY_ACTION_DOWN 0x03
#define KEY_ACTION_UP   0x04

#define BUTTON_ACTION_PRESS   0x07
#define BUTTON_ACTION_RELEASE 0x08

#define BUTTON_LEFT   0x01
#define BUTTON_MIDDLE 0x02
#define BUTTON_RIGHT  0x03
#define BUTTON_X1     0x04 // VLTouch: upstream Limelight.h mouse X1 (missed in first pass; used by CommandManager + ControllerSupport.m).
#define BUTTON_X2     0x05 // VLTouch: upstream Limelight.h mouse X2.

#define LI_TOUCH_EVENT_DOWN 0x01
#define LI_TOUCH_EVENT_UP   0x02
#define LI_TOUCH_EVENT_MOVE 0x03

// Controller button flags. The low 16 bits are the XInput button bits; PADDLE/TOUCHPAD/MISC have no XInput lane.
#define A_FLAG       0x1000
#define B_FLAG       0x2000
#define X_FLAG       0x4000
#define Y_FLAG       0x8000
#define UP_FLAG      0x0001
#define DOWN_FLAG    0x0002
#define LEFT_FLAG    0x0004
#define RIGHT_FLAG   0x0008
#define LB_FLAG      0x0100
#define RB_FLAG      0x0200
#define PLAY_FLAG    0x0010
#define BACK_FLAG    0x0020
#define LS_CLK_FLAG  0x0040
#define RS_CLK_FLAG  0x0080
#define SPECIAL_FLAG 0x0400

#define PADDLE1_FLAG  0x010000
#define PADDLE2_FLAG  0x020000
#define PADDLE3_FLAG  0x040000
#define PADDLE4_FLAG  0x080000
#define TOUCHPAD_FLAG 0x100000 // Touchpad buttons on Sony controllers
#define MISC_FLAG     0x200000 // Share/Mic/Capture/Mute buttons on various controllers

// VLTouch: STICK_CLICK_RATE is deliberately absent. It is not a Limelight.h symbol: VoidLink declares it
// file-local in OnScreenControls.m (`static const double STICK_CLICK_RATE = 100;`), so any definition
// here would rewrite that line and fail to compile.

int LiSendKeyboardEvent(short keyCode, char keyAction, char modifiers);
int LiSendMouseButtonEvent(char action, int button);
int LiSendMouseMoveEvent(short deltaX, short deltaY);
int LiSendMousePositionEvent(short x, short y, short referenceWidth, short referenceHeight);
int LiSendMouseMoveAsMousePositionEvent(short deltaX, short deltaY, short referenceWidth, short referenceHeight);
int LiSendScrollEvent(signed char scrollClicks);
int LiSendHighResScrollEvent(short scrollAmount);
int LiSendHighResHScrollEvent(short scrollAmount);
int LiSendControllerTouchEvent(uint8_t controllerNumber, uint8_t eventType, uint32_t pointerId, float x, float y, float pressure);
int LiSendControllerMotionEvent(uint8_t controllerNumber, uint8_t motionType, float x, float y, float z);

#ifdef __cplusplus
}
#endif

#endif /* VLLI_SHIM_H */
