// VLTouch: S1 sink. Real bodies per docs/fork/TOUCH-PORT.md "Sink contract":
// keyboard -> winios_post_key (VK tables in CommandManager.keyboardButtonMappings,
// CommandManager.swift:212+); mouse buttons/moves/scroll -> winios_pointer
// (MOUSEEVENTF_* table in HardwareInput.MouseButton/event + WheelAccumulator);
// absolute positions scale stream-normalized coords by winios_screen_size.
// Controller touch and motion stay no-ops in wave 1 (no HID publish path in
// GamepadInput yet; TOUCH-PORT.md D4 / R2 section 5).

#import "VLLiShim.h"
#include <pthread.h>

// VLTouch: winios_* prototypes copied verbatim from Winios/Winios.h:44,66 and
// IOSDisplayShim.h:29. No import: app/Madeira is not in HEADER_SEARCH_PATHS
// (PadOutput.m resolves "Winios/…" only because it sits in app/Madeira/).
void winios_post_key(int vk, int down);
void winios_pointer(int x, int y, unsigned int flags, unsigned int data);
void winios_screen_size(int *w, int *h);

// Moonlight modifier bits (upstream Limelight.h): expanded into press/release
// pairs of the generic modifier VKs around the key event. Generic VKs are
// what Madeira itself posts (ContentView.swift:1167-1170 posts 0x10 around a
// shifted char; Library.swift:5498-5499 posts 0x10 for shift).
#define VL_MODIFIER_SHIFT 0x01
#define VL_MODIFIER_CTRL  0x02
#define VL_MODIFIER_ALT   0x04
#define VL_MODIFIER_META  0x08
// VL_MODIFIER_EXTENDED (0x10) is consumed by Moonlight as a scancode-prefix
// hint; winios_post_key derives scan code / extended bit itself
// (driver_ios.c:217-232), so it is dropped here.

#define VL_VK_SHIFT   0x10
#define VL_VK_CONTROL 0x11
#define VL_VK_MENU    0x12
#define VL_VK_LWIN    0x5B

// winios_pointer MOUSEEVENTF_* flags (same table as
// HardwareInput.MouseButton/event and ContentView/GestureZones call sites).
#define VL_MOUSE_MOVE     0x0001
#define VL_MOUSE_ABSOLUTE 0x8000
#define VL_MOUSE_WHEEL    0x0800
#define VL_MOUSE_HWHEEL   0x1000

#define VL_BUTTON_LEFT    0x01
#define VL_BUTTON_MIDDLE  0x02
#define VL_BUTTON_RIGHT   0x03
#define VL_BUTTON_X1      0x04
#define VL_BUTTON_X2      0x05

// Scroll: one notch is WHEEL_DELTA 120 (upstream Limelight.h documents that
// LiSendScrollEvent multiplies clicks by 120; HardwareInput.WheelAccumulator
// posts the same 120-signed deltas via winios_pointer data high word).
#define VL_WHEEL_DELTA 120

// Held-input tracking for VLSink.releaseAll. Guarded by a mutex; the release
// path must not run a callback under the lock (winios_post_key never calls
// back, but keep the discipline anyway: snapshot, clear, then post).
static pthread_mutex_t gHeldLock = PTHREAD_MUTEX_INITIALIZER;
static unsigned short gHeldKeys[256];
static size_t gHeldKeyCount = 0;
static unsigned char gHeldMouseButtons[5]; // VL_BUTTON_* values currently down
static size_t gHeldMouseButtonCount = 0;

static void VLTrackKeyDown(int vk) {
    unsigned short v = (unsigned short)(vk & 0xFFFF);
    pthread_mutex_lock(&gHeldLock);
    for (size_t i = 0; i < gHeldKeyCount; i++) {
        if (gHeldKeys[i] == v) { pthread_mutex_unlock(&gHeldLock); return; }
    }
    if (gHeldKeyCount < sizeof(gHeldKeys) / sizeof(gHeldKeys[0])) {
        gHeldKeys[gHeldKeyCount++] = v;
    }
    pthread_mutex_unlock(&gHeldLock);
}

static void VLTrackKeyUp(int vk) {
    unsigned short v = (unsigned short)(vk & 0xFFFF);
    pthread_mutex_lock(&gHeldLock);
    for (size_t i = 0; i < gHeldKeyCount; i++) {
        if (gHeldKeys[i] == v) {
            gHeldKeys[i] = gHeldKeys[--gHeldKeyCount];
            break;
        }
    }
    pthread_mutex_unlock(&gHeldLock);
}

static void VLTrackMouseDown(int button) {
    pthread_mutex_lock(&gHeldLock);
    for (size_t i = 0; i < gHeldMouseButtonCount; i++) {
        if (gHeldMouseButtons[i] == button) { pthread_mutex_unlock(&gHeldLock); return; }
    }
    if (gHeldMouseButtonCount < sizeof(gHeldMouseButtons)) {
        gHeldMouseButtons[gHeldMouseButtonCount++] = (unsigned char)button;
    }
    pthread_mutex_unlock(&gHeldLock);
}

static void VLTrackMouseUp(int button) {
    pthread_mutex_lock(&gHeldLock);
    for (size_t i = 0; i < gHeldMouseButtonCount; i++) {
        if (gHeldMouseButtons[i] == button) {
            gHeldMouseButtons[i] = gHeldMouseButtons[--gHeldMouseButtonCount];
            break;
        }
    }
    pthread_mutex_unlock(&gHeldLock);
}

static void VLPostKeyDown(int vk) {
    winios_post_key(vk, 1);
    VLTrackKeyDown(vk);
}

static void VLPostKeyUp(int vk) {
    winios_post_key(vk, 0);
    VLTrackKeyUp(vk);
}

static void VLMouseButtonDown(int button, unsigned int flags, unsigned int data) {
    winios_pointer(0, 0, flags, data);
    VLTrackMouseDown(button);
}

static void VLMouseButtonUp(int button, unsigned int flags, unsigned int data) {
    winios_pointer(0, 0, flags, data);
    VLTrackMouseUp(button);
}

// Expand the Moonlight modifiers byte into generic modifier VK down/up pairs
// around the key itself. Modifiers are also tracked so releaseAll frees them
// when a widget is torn down mid-chord.
static void VLPostKeyWithModifiers(int vk, int down, char modifiers) {
    char mods = (char)(modifiers & (VL_MODIFIER_SHIFT | VL_MODIFIER_CTRL | VL_MODIFIER_ALT | VL_MODIFIER_META));
    int modVKs[4];
    int modCount = 0;
    if (mods & VL_MODIFIER_SHIFT) modVKs[modCount++] = VL_VK_SHIFT;
    if (mods & VL_MODIFIER_CTRL)  modVKs[modCount++] = VL_VK_CONTROL;
    if (mods & VL_MODIFIER_ALT)   modVKs[modCount++] = VL_VK_MENU;
    if (mods & VL_MODIFIER_META)  modVKs[modCount++] = VL_VK_LWIN;
    if (down) {
        for (int i = 0; i < modCount; i++) VLPostKeyDown(modVKs[i]);
        VLPostKeyDown(vk);
        for (int i = 0; i < modCount; i++) VLPostKeyUp(modVKs[i]);
    } else {
        for (int i = 0; i < modCount; i++) VLPostKeyDown(modVKs[i]);
        VLPostKeyUp(vk);
        for (int i = 0; i < modCount; i++) VLPostKeyUp(modVKs[i]);
    }
}

int LiSendKeyboardEvent(short keyCode, char keyAction, char modifiers) {
    // Callers pass either a bare VK (CommandManager tables, OnScreenWidgetView
    // direct VK posts) or, for physical-keyboard events, VK with Moonlight's
    // 0x8000 flag bit set (KeyboardSupport.m convention). Strip any flag bits
    // so only the VK reaches winios_post_key.
    int vk = ((int)keyCode) & 0xFFFF;
    vk &= ~0x8000;
    int down = (keyAction == KEY_ACTION_DOWN) ? 1 : 0;
    VLPostKeyWithModifiers(vk, down, modifiers);
    return 0;
}

int LiSendMouseButtonEvent(char action, int button) {
    int down = (action == BUTTON_ACTION_PRESS) ? 1 : 0;
    switch (button) {
        case VL_BUTTON_LEFT:
            if (down) VLMouseButtonDown(button, 0x0002, 0);
            else VLMouseButtonUp(button, 0x0004, 0);
            break;
        case VL_BUTTON_MIDDLE:
            if (down) VLMouseButtonDown(button, 0x0020, 0);
            else VLMouseButtonUp(button, 0x0040, 0);
            break;
        case VL_BUTTON_RIGHT:
            if (down) VLMouseButtonDown(button, 0x0008, 0);
            else VLMouseButtonUp(button, 0x0010, 0);
            break;
        case VL_BUTTON_X1:
            if (down) VLMouseButtonDown(button, 0x0080, 1);
            else VLMouseButtonUp(button, 0x0100, 1);
            break;
        case VL_BUTTON_X2:
            if (down) VLMouseButtonDown(button, 0x0080, 2);
            else VLMouseButtonUp(button, 0x0100, 2);
            break;
        default:
            break;
    }
    return 0;
}

int LiSendMouseMoveEvent(short deltaX, short deltaY) {
    winios_pointer((int)deltaX, (int)deltaY, VL_MOUSE_MOVE, 0);
    return 0;
}

// Widget coordinates are normalized to the stream reference plane
// (OnScreenWidgetView passes view points with superViewWidth/Height);
// queue_ios.c:2314-2321 takes absolute positions in guest screen pixels,
// so scale by the live desktop size, not by 65535.
static void VLPostAbsolutePosition(double x, double y, short referenceWidth, short referenceHeight) {
    int deskW = 0, deskH = 0;
    winios_screen_size(&deskW, &deskH);
    int px = 0, py = 0;
    if (referenceWidth > 0 && referenceHeight > 0) {
        if (deskW > 0 && deskH > 0) {
            px = (int)(x * deskW / referenceWidth);
            py = (int)(y * deskH / referenceHeight);
        }
    } else if (deskW > 0 && deskH > 0) {
        // No reference plane (should not happen from the widgets): assume the
        // coordinates are already guest pixels and clamp them to the desktop.
        px = (int)x;
        py = (int)y;
    }
    if (deskW > 0) {
        if (px < 0) px = 0;
        if (px >= deskW) px = deskW - 1;
    }
    if (deskH > 0) {
        if (py < 0) py = 0;
        if (py >= deskH) py = deskH - 1;
    }
    winios_pointer(px, py, VL_MOUSE_MOVE | VL_MOUSE_ABSOLUTE, 0);
}

int LiSendMousePositionEvent(short x, short y, short referenceWidth, short referenceHeight) {
    VLPostAbsolutePosition((double)x, (double)y, referenceWidth, referenceHeight);
    // Contract mirrors Moonlight: 0 accepted. (The move-as-position variant
    // below is the one whose edge mask the ABSMOUSE widget reads.)
    return 0;
}

// Mirror of Moonlight's virtual-cursor clamp: MoveAsPosition reports which
// reference-plane edge the virtual cursor hit (bit 0 = x edge, bit 1 = y
// edge) so the ABSMOUSE widget can re-center; see the reachedEdgeMask use in
// OnScreenWidgetView (ABSMOUSE case). Tracked in reference-plane units, like
// Moonlight, so the mask matches what the widget expects from its own plane.
static int gMoveAsPositionX = 0;
static int gMoveAsPositionY = 0;

int LiSendMouseMoveAsMousePositionEvent(short deltaX, short deltaY, short referenceWidth, short referenceHeight) {
    int edgeMask = 0;
    if (referenceWidth > 1 && referenceHeight > 1) {
        gMoveAsPositionX += (int)deltaX;
        gMoveAsPositionY += (int)deltaY;
        int maxX = (int)referenceWidth - 1;
        int maxY = (int)referenceHeight - 1;
        if (gMoveAsPositionX < 0) { gMoveAsPositionX = 0; edgeMask |= 0x01; }
        else if (gMoveAsPositionX >= referenceWidth) { gMoveAsPositionX = maxX; edgeMask |= 0x01; }
        if (gMoveAsPositionY < 0) { gMoveAsPositionY = 0; edgeMask |= 0x02; }
        else if (gMoveAsPositionY >= referenceHeight) { gMoveAsPositionY = maxY; edgeMask |= 0x02; }
        VLPostAbsolutePosition((double)gMoveAsPositionX, (double)gMoveAsPositionY, referenceWidth, referenceHeight);
    } else {
        // Degenerate plane: Moonlight returns -3; still post the delta as a
        // relative move so input is not lost.
        winios_pointer((int)deltaX, (int)deltaY, VL_MOUSE_MOVE, 0);
    }
    return edgeMask;
}

int LiSendScrollEvent(signed char scrollClicks) {
    if (scrollClicks == 0) return 0;
    int delta = (int)scrollClicks * VL_WHEEL_DELTA;
    winios_pointer(0, 0, VL_MOUSE_WHEEL, (unsigned int)(int)delta);
    return 0;
}

int LiSendHighResScrollEvent(short scrollAmount) {
    if (scrollAmount == 0) return 0;
    winios_pointer(0, 0, VL_MOUSE_WHEEL, (unsigned int)(int)(int32_t)scrollAmount);
    return 0;
}

int LiSendHighResHScrollEvent(short scrollAmount) {
    if (scrollAmount == 0) return 0;
    winios_pointer(0, 0, VL_MOUSE_HWHEEL, (unsigned int)(int)(int32_t)scrollAmount);
    return 0;
}

// Wave 1 no-ops: filling these needs a DualSense HID publish path in
// GamepadInput (winios_hidpad touch/motion fields), which TOUCH-PORT.md D4
// defers to a later phase. R2 section 5 covers the plumbing; the widget/gyro
// rows of the Sink contract keep working through the stick/mouse shims above.
int LiSendControllerTouchEvent(uint8_t controllerNumber, uint8_t eventType, uint32_t pointerId, float x, float y, float pressure) {
    (void)controllerNumber; (void)eventType; (void)pointerId; (void)x; (void)y; (void)pressure;
    return 0;
}

int LiSendControllerMotionEvent(uint8_t controllerNumber, uint8_t motionType, float x, float y, float z) {
    (void)controllerNumber; (void)motionType; (void)x; (void)y; (void)z;
    return 0;
}

void VLLiReleaseAllHeldInputs(void) {
    unsigned short keys[256];
    size_t keyCount = 0;
    unsigned char buttons[5];
    size_t buttonCount = 0;
    pthread_mutex_lock(&gHeldLock);
    keyCount = gHeldKeyCount;
    for (size_t i = 0; i < keyCount; i++) keys[i] = gHeldKeys[i];
    gHeldKeyCount = 0;
    buttonCount = gHeldMouseButtonCount;
    for (size_t i = 0; i < buttonCount; i++) buttons[i] = gHeldMouseButtons[i];
    gHeldMouseButtonCount = 0;
    pthread_mutex_unlock(&gHeldLock);
    for (size_t i = 0; i < keyCount; i++) winios_post_key((int)keys[i], 0);
    for (size_t i = 0; i < buttonCount; i++) {
        switch (buttons[i]) {
            case VL_BUTTON_LEFT:   winios_pointer(0, 0, 0x0004, 0); break;
            case VL_BUTTON_MIDDLE: winios_pointer(0, 0, 0x0040, 0); break;
            case VL_BUTTON_RIGHT:  winios_pointer(0, 0, 0x0010, 0); break;
            case VL_BUTTON_X1:     winios_pointer(0, 0, 0x0100, 1); break;
            case VL_BUTTON_X2:     winios_pointer(0, 0, 0x0100, 2); break;
            default: break;
        }
    }
    gMoveAsPositionX = 0;
    gMoveAsPositionY = 0;
}
