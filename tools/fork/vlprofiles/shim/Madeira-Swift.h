// Stand-in for the app's generated "Madeira-Swift.h" so the ported ObjC model files
// (app/Madeira/VLTouch/Model/OSCProfile.m, OnScreenButtonState.m) compile on macOS.
// Only the Swift enum constants those two files use are needed. Raw values mirror
// app/Madeira/VLTouch/Compat/VLDataManager.swift and OnScreenWidgetView.swift; main.swift
// cross-checks them against those sources on every run, so a drift fails the build.
#import <Foundation/Foundation.h>

enum {
    ControllerGyroSwitchModeDisabled = 0,   // ControllerGyroSwitchMode.disabled
    TouchModeNative = 1,                    // TouchMode.native
    TouchModeNativeOnly = 4,                // TouchMode.nativeOnly
    WalkSprintKeyActionTypeHold = 0,        // OnScreenWidgetView.WalkSprintKeyActionType.hold
    ControllerElementNull = 0xFFFFFF,       // ControllerElement.null
    UIImpactFeedbackStyleLight = 0,         // UIImpactFeedbackGenerator.FeedbackStyle.light
};
