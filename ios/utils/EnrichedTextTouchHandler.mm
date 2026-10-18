#import "EnrichedTextTouchHandler.h"
#import "EnrichedTextView.h"
#import "extensions/ColorExtension.h"
#import "interfaces/ImageAttachment.h"
#import "interfaces/LinkData.h"
#import "interfaces/MentionParams.h"
#import "interfaces/MentionStyleProps.h"
#import "interfaces/StyleBase.h"
#import "utils/AccessibilityUtils.h"

@implementation EnrichedTextTouchHandler {
  NSRange _activeRange;
  NSString *_activeAttrKey;
  id _activeValue;
}

- (instancetype)initWithView:(EnrichedTextView *)view {
  if (self = [super init]) {
    _view = view;
  }
  return self;
}

- (void)handleTouchBeganAtPoint:(CGPoint)point {
  NSUInteger charIndex = [self characterIndexAtPoint:point];
  NSRange range;
  NSString *key;
  id value = [self findClickableAt:charIndex range:&range key:&key];
  if (value) {
    _activeRange = range;
    _activeAttrKey = key;
    _activeValue = value;
    [self updateVisualsPressed:YES];
  }
}

- (void)handleTouchEndedAtPoint:(CGPoint)point {
  if (!_activeValue) {
    return;
  }

  NSUInteger charIndex = [self characterIndexAtPoint:point];
  if (NSLocationInRange(charIndex, _activeRange)) {
    [self dispatchEvent];
  }

  [self updateVisualsPressed:NO];
  [self reset];
}

- (void)handleTouchCancelled {
  [self updateVisualsPressed:NO];
  [self reset];
}

- (NSUInteger)characterIndexAtPoint:(CGPoint)point {
  UITextView *tv = self.view.textView;
  NSLayoutManager *lm = tv.layoutManager;
  NSTextContainer *tc = tv.textContainer;

  CGPoint textOffset =
      CGPointMake(tv.textContainerInset.left, tv.textContainerInset.top);
  CGPoint locationInContainer =
      CGPointMake(point.x - textOffset.x, point.y - textOffset.y);

  NSUInteger glyphIndex = [lm glyphIndexForPoint:locationInContainer
                                 inTextContainer:tc];
  CGRect glyphRect = [lm boundingRectForGlyphRange:NSMakeRange(glyphIndex, 1)
                                   inTextContainer:tc];

  if (!CGRectContainsPoint(glyphRect, locationInContainer)) {
    return NSNotFound;
  }
  return [lm characterIndexForGlyphAtIndex:glyphIndex];
}

- (id)findClickableAt:(NSUInteger)idx
                range:(NSRangePointer)range
                  key:(NSString **)key {
  if (idx == NSNotFound || idx >= self.view.textView.textStorage.length)
    return nil;

  for (NSString *k in [self clickableKeys]) {
    id val = [self.view.textView.textStorage attribute:k
                                               atIndex:idx
                                        effectiveRange:range];
    if (val) {
      *key = k;
      return val;
    }
  }
  return nil;
}

- (void)updateVisualsPressed:(BOOL)pressed {
  if ([_activeAttrKey isEqualToString:@"EnrichedImage"]) {
    return;
  }

  if (pressed) {
    UIColor *color = nil;
    UIColor *bgColor = nil;

    if ([_activeAttrKey isEqualToString:@"EnrichedMention"]) {
      MentionParams *m = (MentionParams *)_activeValue;
      MentionStyleProps *mProps =
          [self.view.config mentionStylePropsForIndicator:m.indicator];
      color = [mProps pressColor];
      bgColor = [mProps pressBackgroundColor];
    } else {
      color = [self.view.config linkPressColor];
    }

    NSMutableDictionary *newAttrs = [[NSMutableDictionary alloc] init];
    if (color) {
      newAttrs[NSForegroundColorAttributeName] = color;
      newAttrs[NSUnderlineColorAttributeName] = color;
      newAttrs[NSStrikethroughColorAttributeName] = color;
    }
    if (bgColor) {
      newAttrs[NSBackgroundColorAttributeName] =
          [bgColor colorWithResolvedAlpha];
    }

    [self.view.textView.textStorage addAttributes:newAttrs range:_activeRange];
  } else {
    // REVERT using the Style Engine in the View
    for (StyleBase *style in self.view.stylesDict.allValues) {
      NSString *styleKey = [style getKey];
      // If the style key matches exactly (Mentions)
      // OR if both the style and the active key are Link-related
      BOOL isMatch = [styleKey isEqualToString:_activeAttrKey];
      BOOL isLinkMatch = ([_activeAttrKey containsString:@"Link"] &&
                          [styleKey containsString:@"Link"]);

      if (isMatch || isLinkMatch) {
        [style applyStyling:_activeRange];
      }
    }
  }
}

- (void)dispatchEvent {
  [self dispatchEventForKey:_activeAttrKey
                      value:_activeValue
                      range:_activeRange];
}

- (void)dispatchEventForKey:(NSString *)key
                      value:(id)value
                      range:(NSRange)range {
  if ([key containsString:@"Link"]) {
    [self.view emitOnLinkPressEvent:((LinkData *)value).url];
  } else if ([key isEqualToString:@"EnrichedMention"]) {
    [self.view emitOnMentionPressEvent:(MentionParams *)value];
  } else if ([key isEqualToString:@"EnrichedImage"]) {
    ImageAttachment *attachment =
        [self.view.textView.textStorage attribute:NSAttachmentAttributeName
                                          atIndex:range.location
                                   effectiveRange:NULL];
    if ([attachment isKindOfClass:[ImageAttachment class]]) {
      [self.view emitOnImagePressEvent:attachment];
    }
  }
}

- (NSArray<UIAccessibilityCustomAction *> *)accessibilityActions {
  NSTextStorage *storage = self.view.textView.textStorage;
  NSString *text = storage.string;
  NSMutableArray<NSDictionary *> *clickables = [NSMutableArray array];

  for (NSString *key in [self clickableKeys]) {
    [storage enumerateAttribute:key
                        inRange:NSMakeRange(0, storage.length)
                        options:0
                     usingBlock:^(id value, NSRange range, BOOL *stop) {
                       if (value) {
                         [clickables addObject:@{
                           @"key" : key,
                           @"value" : value,
                           @"range" : [NSValue valueWithRange:range]
                         }];
                       }
                     }];
  }

  [clickables sortUsingComparator:^NSComparisonResult(NSDictionary *a,
                                                      NSDictionary *b) {
    NSUInteger aLocation = [a[@"range"] rangeValue].location;
    NSUInteger bLocation = [b[@"range"] rangeValue].location;
    if (aLocation == bLocation) {
      return NSOrderedSame;
    }
    return aLocation < bLocation ? NSOrderedAscending : NSOrderedDescending;
  }];

  NSMutableArray<UIAccessibilityCustomAction *> *actions =
      [NSMutableArray array];
  __weak EnrichedTextTouchHandler *weakSelf = self;
  for (NSDictionary *clickable in clickables) {
    NSString *key = clickable[@"key"];
    id value = clickable[@"value"];
    NSRange range = [clickable[@"range"] rangeValue];
    NSString *spoken = [AccessibilityUtils spokenTextInRange:range
                                                    ofString:text];

    NSString *name;
    if ([key containsString:@"Link"]) {
      NSString *linkText = spoken.length > 0 ? spoken : ((LinkData *)value).url;
      name = [NSString stringWithFormat:@"Open link: %@", linkText];
    } else if ([key isEqualToString:@"EnrichedMention"]) {
      NSString *mentionText =
          spoken.length > 0 ? spoken : ((MentionParams *)value).text;
      name = [NSString stringWithFormat:@"Open mention: %@", mentionText];
    } else {
      name = @"Open image";
    }

    [actions
        addObject:[[UIAccessibilityCustomAction alloc]
                       initWithName:name
                      actionHandler:^BOOL(UIAccessibilityCustomAction *action) {
                        [weakSelf dispatchEventForKey:key
                                                value:value
                                                range:range];
                        return YES;
                      }]];
  }

  return actions;
}

- (NSArray<NSString *> *)clickableKeys {
  return @[
    @"EnrichedManualLink", @"EnrichedAutomaticLink", @"EnrichedMention",
    @"EnrichedImage"
  ];
}

- (void)reset {
  _activeValue = nil;
  _activeAttrKey = nil;
  _activeRange = NSMakeRange(0, 0);
}
@end
