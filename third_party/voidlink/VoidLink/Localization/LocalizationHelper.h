//
//  LocalizationHelper.h
//  VoidLink
//
//  Created by True砖家 on 2024/6/30.
//  Copyright © 2024 True砖家 on Bilibili. All rights reserved.
//

#ifndef LocalizationHelper_h
#define LocalizationHelper_h

#import <Foundation/Foundation.h>

@interface LocalizationHelper : NSObject

// Method to get localized string with format arguments
+ (NSString *)localizedStringForKey:(NSString *)key, ... NS_FORMAT_FUNCTION(1,2);

@end

#endif /* LocalizationHelper_h */
