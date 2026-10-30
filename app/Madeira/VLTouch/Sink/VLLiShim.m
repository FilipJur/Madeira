// VLTouch: no-op Li* bodies so the ported widget code links before the sink exists.

#import "VLLiShim.h"

int LiSendKeyboardEvent(short keyCode, char keyAction, char modifiers) {
    // VLTouch: no-op; S1 implements.
    return 0;
}

int LiSendMouseButtonEvent(char action, int button) {
    // VLTouch: no-op; S1 implements.
    return 0;
}

int LiSendMouseMoveEvent(short deltaX, short deltaY) {
    // VLTouch: no-op; S1 implements.
    return 0;
}

int LiSendMousePositionEvent(short x, short y, short referenceWidth, short referenceHeight) {
    // VLTouch: no-op; S1 implements.
    return 0;
}

int LiSendMouseMoveAsMousePositionEvent(short deltaX, short deltaY, short referenceWidth, short referenceHeight) {
    // VLTouch: no-op; S1 implements.
    return 0;
}

int LiSendScrollEvent(signed char scrollClicks) {
    // VLTouch: no-op; S1 implements.
    return 0;
}

int LiSendHighResScrollEvent(short scrollAmount) {
    // VLTouch: no-op; S1 implements.
    return 0;
}

int LiSendHighResHScrollEvent(short scrollAmount) {
    // VLTouch: no-op; S1 implements.
    return 0;
}

int LiSendControllerTouchEvent(uint8_t controllerNumber, uint8_t eventType, uint32_t pointerId, float x, float y, float pressure) {
    // VLTouch: no-op; S1 implements.
    return 0;
}

int LiSendControllerMotionEvent(uint8_t controllerNumber, uint8_t motionType, float x, float y, float z) {
    // VLTouch: no-op; S1 implements.
    return 0;
}
