#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AccessibilityUtils : NSObject

+ (NSString *)spokenTextInRange:(NSRange)range ofString:(NSString *)string;

+ (nullable NSArray<UIAccessibilityCustomAction *> *)
    mergeActions:(nullable NSArray<UIAccessibilityCustomAction *> *)first
            with:(nullable NSArray<UIAccessibilityCustomAction *> *)second;

@end

NS_ASSUME_NONNULL_END
