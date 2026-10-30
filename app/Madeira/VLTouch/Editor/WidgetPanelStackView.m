//
//  WidgetPanelStackView.h
//  VoidLink
//
//  Created by True砖家 on 2025/6/19.
//  Copyright © True砖家 on Bilibili. All rights reserved.
//


#import "WidgetPanelStackView.h"

@implementation WidgetPanelStackView

- (BOOL) pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if ([UIDevice currentDevice].userInterfaceIdiom != UIUserInterfaceIdiomPhone) return [super pointInside:point withEvent:event];
    BOOL touchedWithinMask;
    CAShapeLayer *mask = (CAShapeLayer *)self.layer.mask;
    if (mask && mask.path) {
        // 注意：mask 的坐标系是以 view.layer 为基准的
        touchedWithinMask = CGPathContainsPoint(mask.path, NULL, point, NO);
    }
    else touchedWithinMask = YES;
    return  touchedWithinMask;
}

@end
