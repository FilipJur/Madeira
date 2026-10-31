#import "VLCoderShim.h"

@implementation NSCoder (VLCoderShim)

- (void)encodeCGPoint:(CGPoint)point forKey:(NSString *)key {
    [self encodeObject:[NSString stringWithFormat:@"{%g, %g}", (double)point.x, (double)point.y] forKey:key];
}

- (CGPoint)decodeCGPointForKey:(NSString *)key {
    NSString *s = [self decodeObjectOfClass:[NSString class] forKey:key];
    double x = 0, y = 0;
    if (s && sscanf(s.UTF8String, "{%lf, %lf}", &x, &y) == 2) {
        return CGPointMake(x, y);
    }
    return CGPointZero;
}

@end

// Writes only the keys the real decoders read without a containsValueForKey: guard.
@interface VLMinimalButtonState : NSObject <NSCoding>
@end
@implementation VLMinimalButtonState
- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:@"" forKey:@"name"];
    [c encodeObject:@"" forKey:@"alias"];
    [c encodeInt:1 forKey:@"buttonType"];
    [c encodeInt:0 forKey:@"mouseButtonAction"];
    [c encodeCGPoint:CGPointMake(0.5, 0.5) forKey:@"position"];
    [c encodeBool:NO forKey:@"isHidden"];
    [c encodeFloat:1 forKey:@"widthFactor"];
    [c encodeFloat:1 forKey:@"heightFactor"];
    [c encodeFloat:0 forKey:@"stickIndicatorOffset"];
    [c encodeFloat:0 forKey:@"oscLayerSizeFactor"];
    [c encodeFloat:0 forKey:@"borderWidth"];
    [c encodeObject:@"default" forKey:@"widgetShape"];
    [c encodeFloat:0 forKey:@"minStickOffset"];
}
- (instancetype)initWithCoder:(NSCoder *)c { return [super init]; }
@end

@interface VLMinimalProfile : NSObject <NSCoding>
@end
@implementation VLMinimalProfile
- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:@"" forKey:@"name"];
    [c encodeObject:[NSMutableArray array] forKey:@"buttonStates"];
    [c encodeBool:NO forKey:@"isSelected"];
}
- (instancetype)initWithCoder:(NSCoder *)c { return [super init]; }
@end

static id VLDecodeAs(Class minimal, NSString *realName) {
    NSKeyedArchiver *a = [[NSKeyedArchiver alloc] initRequiringSecureCoding:NO];
    [a setClassName:realName forClass:minimal];
    [a encodeObject:[[minimal alloc] init] forKey:NSKeyedArchiveRootObjectKey];
    [a finishEncoding];
    NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingFromData:a.encodedData error:nil];
    u.requiresSecureCoding = NO;
    return [u decodeObjectForKey:NSKeyedArchiveRootObjectKey];
}

id VLNewDefaultButtonState(void) { return VLDecodeAs([VLMinimalButtonState class], @"OnScreenButtonState"); }
id VLNewDefaultProfile(void) { return VLDecodeAs([VLMinimalProfile class], @"OSCProfile"); }
