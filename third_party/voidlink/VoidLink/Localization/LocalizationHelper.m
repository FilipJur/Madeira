//
//  LocalizationHelper.m
//  VoidLink
//
//  Created by True砖家 on 2024/6/30.
//  Copyright © 2024 True砖家 on Bilibili. All rights reserved.
//

#import "LocalizationHelper.h"

@implementation LocalizationHelper

+ (NSString *)localizedStringForKey:(NSString *)key, ... {
    va_list args;
    va_start(args, key);

    NSString *format = NSLocalizedStringFromTable(key, @"Localizable", nil);
    NSString *result = [[NSString alloc] initWithFormat:format arguments:args];

    va_end(args);
    return result;
}

@end
