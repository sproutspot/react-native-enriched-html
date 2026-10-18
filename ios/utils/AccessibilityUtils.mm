#import "AccessibilityUtils.h"

@implementation AccessibilityUtils

+ (NSString *)spokenTextInRange:(NSRange)range ofString:(NSString *)string {
  if (NSMaxRange(range) > string.length) {
    return @"";
  }
  NSString *substring = [string substringWithRange:range];
  substring = [substring stringByReplacingOccurrencesOfString:@"\u200B"
                                                   withString:@""];
  substring = [substring stringByReplacingOccurrencesOfString:@"\uFFFC"
                                                   withString:@""];
  return [substring
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
}

+ (nullable NSArray<UIAccessibilityCustomAction *> *)
    mergeActions:(nullable NSArray<UIAccessibilityCustomAction *> *)first
            with:(nullable NSArray<UIAccessibilityCustomAction *> *)second {
  if (first.count == 0) {
    return second.count > 0 ? second : nil;
  }
  if (second.count == 0) {
    return first;
  }
  return [first arrayByAddingObjectsFromArray:second];
}

@end
