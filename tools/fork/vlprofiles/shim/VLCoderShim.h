// UIKit-only pieces the ported model files rely on, for the macOS generator.
#import <Foundation/Foundation.h>

// UIKit's NSCoder geometry additions. UIKit archives a CGPoint as the string "{x, y}"
// (NSStringFromCGPoint); the bundled widgetTemplates*.bin positions confirm this
// (main.swift prints them in the template decode).
@interface NSCoder (VLCoderShim)
- (void)encodeCGPoint:(CGPoint)point forKey:(NSString *)key;
- (CGPoint)decodeCGPointForKey:(NSString *)key;
@end

// Fresh model objects whose unspecified fields carry the *decoder's own* fallback values:
// the object is archived with only the keys initWithCoder reads unconditionally, then decoded
// by the real model class. So generator defaults can never drift from the app's decoder.
id VLNewDefaultButtonState(void);
id VLNewDefaultProfile(void);
