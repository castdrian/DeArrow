#import "Metadata.h"

#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>

@implementation VideoMetadataRecord

- (instancetype)initWithVideoID:(NSString *)videoID
                          title:(NSString *)title
                        channel:(NSString *)channel
{
    self = [super init];
    if (self)
    {
        _videoID = [videoID copy];
        _title   = [title copy];
        _channel = [channel copy];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

@end

static NSString *ValidVideoID(NSString *value)
{
    if (![value isKindOfClass:[NSString class]] || value.length != 11)
        return nil;
    NSCharacterSet *allowed =
        [NSCharacterSet characterSetWithCharactersInString:
                            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
    if ([value rangeOfCharacterFromSet:[allowed invertedSet]].location != NSNotFound)
        return nil;
    return value;
}

static id IvarObjectValue(id object, NSString *key)
{
    if (!object || key.length == 0)
        return nil;
    Ivar ivar = class_getInstanceVariable(object_getClass(object),
                                          [NSString stringWithFormat:@"_%@", key].UTF8String);
    if (!ivar)
        ivar = class_getInstanceVariable(object_getClass(object), key.UTF8String);
    if (!ivar)
        return nil;
    const char *type = ivar_getTypeEncoding(ivar);
    return type && type[0] == '@' ? object_getIvar(object, ivar) : nil;
}

static id DirectObjectValue(id object, NSString *key)
{
    if (!object || key.length == 0 || object == [NSNull null])
        return nil;
    if ([object isKindOfClass:[NSDictionary class]])
        return [(NSDictionary *) object objectForKey:key];
    SEL selector = NSSelectorFromString(key);
    if (![object respondsToSelector:selector])
        return IvarObjectValue(object, key);
    Method      method   = class_getInstanceMethod(object_getClass(object), selector);
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    if (!encoding || encoding[0] != '@' || method_getNumberOfArguments(method) != 2)
        return IvarObjectValue(object, key);
    @try
    {
        id value = ((id (*)(id, SEL)) objc_msgSend)(object, selector);
        return value ?: IvarObjectValue(object, key);
    }
    @catch (__unused NSException *exception)
    {
        return IvarObjectValue(object, key);
    }
}

static id DirectArgumentValue(id object, NSString *selectorName, NSString *key)
{
    if (!object || selectorName.length == 0 || key.length == 0)
        return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector])
        return nil;
    Method      method   = class_getInstanceMethod(object_getClass(object), selector);
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    if (!encoding || encoding[0] != '@' || method_getNumberOfArguments(method) != 3)
        return nil;
    @try
    {
        return ((id (*)(id, SEL, id)) objc_msgSend)(object, selector, key);
    }
    @catch (__unused NSException *exception)
    {
        return nil;
    }
}

static id ExplicitValue(id object, NSString *key)
{
    if (!object || key.length == 0 || object == [NSNull null])
        return nil;
    id value = DirectObjectValue(object, key);
    if (value)
        return value;
    for (NSString *selectorName in @[ @"propertyForKey:", @"elementForKey:" ])
    {
        value = DirectArgumentValue(object, selectorName, key);
        if (value)
            return value;
    }
    return nil;
}

static NSString *TextFromValueAtDepth(id value, NSUInteger depth)
{
    if (depth > 4)
        return nil;
    if ([value isKindOfClass:[NSString class]])
        return [value
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([value isKindOfClass:[NSAttributedString class]])
        return [TextFromValueAtDepth([(NSAttributedString *) value string], depth + 1) copy];
    if ([value isKindOfClass:[NSURL class]])
        return [(NSURL *) value absoluteString];
    @try
    {
        if ([value respondsToSelector:@selector(stringWithFormattingRemoved)])
        {
            NSString *text = ((NSString * (*)(id, SEL))
                                  objc_msgSend)(value, @selector(stringWithFormattingRemoved));
            if (text.length > 0)
                return TextFromValueAtDepth(text, depth + 1);
        }
        if ([value respondsToSelector:@selector(string)])
        {
            NSString *text = ((NSString * (*)(id, SEL)) objc_msgSend)(value, @selector(string));
            if (text.length > 0)
                return TextFromValueAtDepth(text, depth + 1);
        }
    }
    @catch (__unused NSException *exception)
    {
    }
    if ([value isKindOfClass:[NSDictionary class]])
    {
        NSString *text = TextFromValueAtDepth(value[@"text"], depth + 1);
        if (text.length > 0)
            return text;
        NSString *simpleText = TextFromValueAtDepth(value[@"simpleText"], depth + 1);
        if (simpleText.length > 0)
            return simpleText;
        NSString *accessibility = TextFromValueAtDepth(value[@"accessibility"], depth + 1);
        if (accessibility.length > 0)
            return accessibility;
        NSArray *runs = value[@"runs"];
        if ([runs isKindOfClass:[NSArray class]])
        {
            NSMutableString *text     = [NSMutableString string];
            NSUInteger       runCount = MIN(runs.count, 64);
            for (NSUInteger index = 0; index < runCount; index++)
            {
                id        run     = runs[index];
                NSString *runText = TextFromValueAtDepth(
                    [run isKindOfClass:[NSDictionary class]] ? run[@"text"] : nil, depth + 1);
                if (runText.length > 0)
                    [text appendString:runText];
            }
            return text.length > 0 ? text : nil;
        }
    }
    if ([value isKindOfClass:[NSArray class]])
    {
        NSMutableString *text  = [NSMutableString string];
        NSUInteger       count = 0;
        for (id item in (NSArray *) value)
        {
            if (count++ >= 32)
                break;
            NSString *itemText = TextFromValueAtDepth(item, depth + 1);
            if (itemText.length == 0)
                continue;
            if (text.length > 0)
                [text appendString:@" "];
            [text appendString:itemText];
        }
        return text.length > 0 ? text : nil;
    }
    for (NSString *key in
         @[ @"text", @"string", @"plainText", @"simpleText", @"accessibilityLabel" ])
    {
        NSString *text = TextFromValueAtDepth(ExplicitValue(value, key), depth + 1);
        if (text.length > 0)
            return text;
    }
    return nil;
}

static NSString *TextFromValue(id value)
{
    return TextFromValueAtDepth(value, 0);
}

static NSString *TrimmedText(NSString *text)
{
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL IsSyntheticChannelValue(NSString *text)
{
    NSString *candidate = TrimmedText(text).lowercaseString;
    return [candidate isEqualToString:@"action menu"] ||
           [candidate isEqualToString:@"more actions"] ||
           [candidate isEqualToString:@"sponsored"] || [candidate isEqualToString:@"verified"] ||
           [candidate isEqualToString:@"live"];
}

static BOOL IsLikelyChannelText(NSString *text, NSString *title)
{
    NSString *candidate = TrimmedText(text);
    NSString *lowercase = candidate.lowercaseString;
    if (candidate.length < 2 || candidate.length > 120 ||
        [candidate caseInsensitiveCompare:title] == NSOrderedSame ||
        IsSyntheticChannelValue(candidate))
        return NO;
    for (NSString *excluded in @[
             @" views",        @" view",       @" ago",          @" subscribers",
             @" sponsored",    @"subscribe",   @"watch later",   @"playlist",
             @"share",         @"description", @"clear screen",  @"not interested",
             @"send feedback", @"home",        @"shorts",        @"subscriptions",
             @"you",           @"search",      @"notifications", @"settings"
         ])
    {
        if ([lowercase containsString:excluded])
            return NO;
    }
    return YES;
}

static BOOL IsFeedDurationText(NSString *text)
{
    NSString *candidate = TrimmedText(text).lowercaseString;
    if (candidate.length == 0)
        return NO;
    static NSRegularExpression *durationRegex;
    static NSRegularExpression *clockRegex;
    static dispatch_once_t      onceToken;
    dispatch_once(&onceToken, ^{
        durationRegex = [NSRegularExpression
            regularExpressionWithPattern:@"^[0-9][0-9:., "
                                         @"]*(seconds?|minutes?|hours?|sekunden?|minuten?|stunden?|"
                                         @"segundos?|minutos?|horas?|秒|分|時間)"
                                 options:NSRegularExpressionCaseInsensitive
                                   error:nil];
        clockRegex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9]+(?::[0-9]{2}){1,2}$"
                                                               options:0
                                                                 error:nil];
    });
    NSRange range = NSMakeRange(0, candidate.length);
    return [durationRegex firstMatchInString:candidate options:0 range:range] != nil ||
           [clockRegex firstMatchInString:candidate options:0 range:range] != nil;
}

static BOOL IsFeedStatsText(NSString *text)
{
    NSString *candidate = TrimmedText(text).lowercaseString;
    for (NSString *marker in @[
             @" views", @" view", @" ago", @" subscribers", @" aufrufe", @" vor ",
             @" visualizaciones", @" visualizações", @" hace ", @"播放", @" مشاهدة"
         ])
    {
        if ([candidate containsString:marker])
            return YES;
    }
    return [candidate hasPrefix:@"play "] || [candidate hasPrefix:@"video "] ||
           [candidate hasPrefix:@"short "] || [candidate isEqualToString:@"verified"];
}

static NSString *TitleFromAccessibleText(NSString *text)
{
    NSString *candidate  = TrimmedText(text);
    NSArray  *components = [candidate componentsSeparatedByString:@" - "];
    if (components.count < 2)
        return nil;
    for (NSUInteger index = 1; index < components.count; index++)
    {
        if (!IsFeedDurationText(components[index]))
            continue;
        NSString *title = TrimmedText(
            [[components subarrayWithRange:NSMakeRange(0, index)] componentsJoinedByString:@" - "]);
        return title.length > 0 ? title : nil;
    }
    return nil;
}

static NSString *ChannelFromAccessibleText(NSString *text)
{
    NSString *candidate = TrimmedText(text);
    for (NSString *marker in @[ @"go to channel ", @"go to channel:" ])
    {
        NSRange markerRange = [candidate rangeOfString:marker options:NSCaseInsensitiveSearch];
        if (markerRange.location == NSNotFound)
            continue;
        NSString *channel   = TrimmedText([candidate substringFromIndex:NSMaxRange(markerRange)]);
        NSRange   separator = [channel rangeOfString:@" - "];
        if (separator.location != NSNotFound)
            channel = TrimmedText([channel substringToIndex:separator.location]);
        if (IsLikelyChannelText(channel, nil))
            return channel;
    }
    return nil;
}

static NSString *ChannelFromFeedAccessibleText(NSString *text, NSString *title)
{
    NSArray *components = [TrimmedText(text) componentsSeparatedByString:@" - "];
    if (components.count < 3)
        return nil;
    NSUInteger durationIndex = NSNotFound;
    for (NSUInteger index = 1; index < components.count; index++)
    {
        if (IsFeedDurationText(components[index]))
        {
            durationIndex = index;
            break;
        }
    }
    if (durationIndex == NSNotFound)
        return nil;
    NSUInteger limit = MIN(components.count, durationIndex + 4);
    for (NSUInteger index = durationIndex + 1; index < limit; index++)
    {
        NSString *channel = TrimmedText(components[index]);
        if ([channel isEqualToString:title] || IsFeedStatsText(channel))
            continue;
        if (IsLikelyChannelText(channel, title))
            return channel;
    }
    return nil;
}

static NSString *TitleFromElementsAccessibleText(NSString *text, NSString *channel)
{
    NSString *candidate = TrimmedText(text);
    if (channel.length > 0)
    {
        NSString *marker = [NSString stringWithFormat:@", %@ - ", channel];
        NSRange   range  = [candidate rangeOfString:marker options:NSCaseInsensitiveSearch];
        if (range.location != NSNotFound)
            return TrimmedText([candidate substringToIndex:range.location]);
    }
    NSArray *components = [candidate componentsSeparatedByString:@" - "];
    if (components.count < 2)
        return nil;
    NSMutableArray *titleComponents = [NSMutableArray array];
    for (NSString *component in components)
    {
        if (IsFeedStatsText(component) || [component.lowercaseString hasPrefix:@"play "])
            break;
        if (titleComponents.count > 0 && IsLikelyChannelText(component, nil))
            break;
        [titleComponents addObject:component];
    }
    NSString *title = TrimmedText([titleComponents componentsJoinedByString:@" - "]);
    return title.length > 0 ? title : nil;
}

static void RecordParsedField(NSMutableDictionary *fields, NSString *key, NSString *value)
{
    NSString *candidate = TrimmedText(value);
    if (candidate.length == 0 || candidate.length > 240 || fields[key])
        return;
    if ([key isEqualToString:@"channel"] && IsSyntheticChannelValue(candidate))
        return;
    fields[key] = candidate;
}

static void RecordParsedText(NSMutableDictionary *fields, NSString *text)
{
    NSString *candidate = TrimmedText(text);
    if (candidate.length == 0)
        return;
    RecordParsedField(fields, @"title", TitleFromAccessibleText(candidate));
    RecordParsedField(fields, @"channel", ChannelFromAccessibleText(candidate));
    RecordParsedField(fields, @"channel",
                      ChannelFromFeedAccessibleText(candidate, fields[@"title"]));
    RecordParsedField(fields, @"title",
                      TitleFromElementsAccessibleText(candidate, fields[@"channel"]));
    if ([candidate hasPrefix:@"@"] && IsLikelyChannelText(candidate, nil))
        RecordParsedField(fields, @"channel", candidate);
}

static NSString *ValueFromKeys(id object, NSArray<NSString *> *keys)
{
    for (NSString *key in keys)
    {
        NSString *value = TextFromValue(ExplicitValue(object, key));
        if (value.length > 0)
            return value;
    }
    return nil;
}

static NSString *VideoIDFromURLObject(id value)
{
    NSURL *URL = [value isKindOfClass:[NSURL class]]
                     ? value
                     : [NSURL URLWithString:TextFromValue(value) ?: @""];
    if (!URL)
        return nil;
    NSURLComponents *components = [NSURLComponents componentsWithURL:URL
                                             resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems)
    {
        NSString *name = item.name.lowercaseString;
        if ([name isEqualToString:@"v"] || [name isEqualToString:@"videoid"] ||
            [name isEqualToString:@"video_id"])
        {
            NSString *candidate = ValidVideoID(item.value);
            if (candidate)
                return candidate;
        }
    }
    NSArray *parts = [URL.path componentsSeparatedByString:@"/"];
    for (NSUInteger index = 0; index + 1 < parts.count; index++)
    {
        NSString *part = [parts[index] lowercaseString];
        if ([part isEqualToString:@"vi"] || [part isEqualToString:@"vi_webp"] ||
            [part isEqualToString:@"embed"] || [part isEqualToString:@"shorts"] ||
            [part isEqualToString:@"live"])
        {
            NSString *candidate = ValidVideoID(parts[index + 1]);
            if (candidate)
                return candidate;
        }
    }
    if ([URL.host.lowercaseString isEqualToString:@"youtu.be"])
    {
        for (NSInteger index = (NSInteger) parts.count - 1; index >= 0; index--)
        {
            NSString *candidate = ValidVideoID(parts[(NSUInteger) index]);
            if (candidate)
                return candidate;
        }
    }
    return nil;
}

static NSString *VideoIDFromValue(id value)
{
    NSString *direct = ValidVideoID(TextFromValue(value));
    if (direct)
        return direct;
    NSArray<NSString *> *keys = @[
        @"videoId", @"videoID", @"video_id", @"videoIdentifier", @"contentVideoID",
        @"contentVideoId", @"videoIDString", @"currentVideoID", @"currentVideoId", @"activeVideoID",
        @"activeVideoId", @"playerResponseVideoID", @"watchVideoID", @"identifier", @"id"
    ];
    for (NSString *key in keys)
    {
        NSString *candidate = ValidVideoID(TextFromValue(ExplicitValue(value, key)));
        if (candidate)
            return candidate;
    }
    return VideoIDFromURLObject(value);
}

static NSString *IDFromContainer(id container)
{
    NSString *videoID = VideoIDFromValue(container);
    if (videoID)
        return videoID;
    for (NSString *key in @[
             @"video",
             @"videoRenderer",
             @"videoWithContextRenderer",
             @"compactVideoRenderer",
             @"shortsVideoRenderer",
             @"reelItemRenderer",
             @"richItemRenderer",
             @"navigationEndpoint",
             @"watchEndpoint",
             @"command",
             @"model",
             @"entry",
             @"elementEntry",
             @"nodeModel",
             @"collectionElement",
             @"strongComponent",
             @"weakComponent",
             @"owningReference",
             @"children",
             @"extendedProperties",
             @"nodeContext",
             @"displayNode",
             @"parentResponder",
             @"cell",
             @"renderer",
             @"element",
             @"instance",
             @"content",
             @"currentVideo",
             @"contentVideo",
             @"activeVideo",
             @"videoDetails",
             @"videoData",
             @"watchModel",
             @"reelModel",
             @"playerResponse",
             @"watchNextResponse",
             @"watchResponse",
             @"playbackData",
             @"contentPlaybackData",
             @"response",
             @"singleVideoController",
             @"singleVideo",
             @"watchController",
             @"videoController",
             @"player",
             @"contentView",
             @"parentController"
         ])
    {
        videoID = VideoIDFromValue(ExplicitValue(container, key));
        if (videoID)
            return videoID;
    }
    return nil;
}

static NSString *TitleFromContainer(id container)
{
    NSString *title = ValueFromKeys(container, @[
        @"title", @"videoTitle", @"headline", @"titleText", @"displayTitle", @"videoTitleText"
    ]);
    if (title.length > 0)
        return title;
    for (NSString *key in @[
             @"video",
             @"videoRenderer",
             @"videoWithContextRenderer",
             @"compactVideoRenderer",
             @"shortsVideoRenderer",
             @"reelItemRenderer",
             @"model",
             @"entry",
             @"elementEntry",
             @"nodeModel",
             @"collectionElement",
             @"strongComponent",
             @"weakComponent",
             @"owningReference",
             @"children",
             @"extendedProperties",
             @"nodeContext",
             @"displayNode",
             @"parentResponder",
             @"cell",
             @"renderer",
             @"element",
             @"instance",
             @"content",
             @"currentVideo",
             @"contentVideo",
             @"activeVideo",
             @"videoDetails",
             @"videoData",
             @"singleVideoController",
             @"singleVideo",
             @"watchController",
             @"videoController"
         ])
    {
        title = ValueFromKeys(ExplicitValue(container, key), @[
            @"title", @"videoTitle", @"headline", @"titleText", @"displayTitle", @"videoTitleText"
        ]);
        if (title.length > 0)
            return title;
    }
    return nil;
}

static NSString *ChannelFromContainer(id container)
{
    NSString *channel = ValueFromKeys(container, @[
        @"channelName", @"channelTitle", @"ownerName", @"ownerDisplayName", @"author",
        @"authorName", @"owner", @"channelHandle", @"byline", @"shortBylineText", @"longBylineText"
    ]);
    if (channel.length > 0)
        return channel;
    for (NSString *key in @[
             @"video",
             @"videoRenderer",
             @"videoWithContextRenderer",
             @"compactVideoRenderer",
             @"shortsVideoRenderer",
             @"reelItemRenderer",
             @"model",
             @"entry",
             @"elementEntry",
             @"nodeModel",
             @"collectionElement",
             @"strongComponent",
             @"weakComponent",
             @"owningReference",
             @"children",
             @"extendedProperties",
             @"nodeContext",
             @"displayNode",
             @"parentResponder",
             @"cell",
             @"renderer",
             @"element",
             @"instance",
             @"content",
             @"currentVideo",
             @"contentVideo",
             @"activeVideo",
             @"videoDetails",
             @"videoData",
             @"singleVideoController",
             @"singleVideo",
             @"watchController",
             @"videoController"
         ])
    {
        channel = ValueFromKeys(ExplicitValue(container, key), @[
            @"channelName", @"channelTitle", @"ownerName", @"ownerDisplayName", @"author",
            @"authorName", @"owner", @"channelHandle", @"byline", @"shortBylineText",
            @"longBylineText"
        ]);
        if (channel.length > 0)
            return channel;
    }
    return nil;
}

static NSDictionary *ElementProperties(id element)
{
    if (!element)
        return nil;
    for (NSString *key in @[ @"allProperties", @"properties", @"data" ])
    {
        id value = ExplicitValue(element, key);
        if ([value isKindOfClass:[NSDictionary class]])
            return value;
    }
    return nil;
}

static BOOL ReadRawVarint(const uint8_t *bytes, NSUInteger length, NSUInteger *offset,
                          uint64_t *value)
{
    if (!bytes || !offset || !value)
        return NO;
    uint64_t result = 0;
    for (NSUInteger shift = 0; *offset < length && shift <= 63; shift += 7)
    {
        uint8_t byte = bytes[(*offset)++];
        result |= ((uint64_t) (byte & 0x7f)) << shift;
        if ((byte & 0x80) == 0)
        {
            *value = result;
            return YES;
        }
    }
    return NO;
}

static BOOL IsPrintableRawData(const uint8_t *bytes, NSUInteger length)
{
    if (!bytes || length == 0 || length > 4096)
        return NO;
    NSString *text = [[NSString alloc] initWithBytes:bytes
                                              length:length
                                            encoding:NSUTF8StringEncoding];
    if (text.length == 0)
        return NO;
    for (NSUInteger index = 0; index < text.length; index++)
    {
        unichar character = [text characterAtIndex:index];
        if (character < 0x20 && character != '\n' && character != '\r' && character != '\t')
            return NO;
    }
    return YES;
}

static void RecordRawField(NSMutableDictionary *fields, NSString *key, NSString *value)
{
    NSString *candidate =
        [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (candidate.length == 0 || candidate.length > 240 || [(NSString *) fields[key] length] > 0)
        return;
    if ([key isEqualToString:@"channel"] &&
        [@[ @"action menu", @"more actions", @"sponsored", @"verified", @"live" ]
            containsObject:candidate.lowercaseString])
        return;
    fields[key] = candidate;
}

static void RecordRawMessage(NSMutableDictionary *fields, const uint8_t *bytes, NSUInteger length,
                             NSUInteger depth, NSUInteger *budget)
{
    if (!bytes || length == 0 || depth > 8 || !budget || *budget == 0)
        return;
    NSUInteger offset = 0;
    while (offset < length && *budget > 0)
    {
        uint64_t tag = 0;
        if (!ReadRawVarint(bytes, length, &offset, &tag))
            return;
        uint64_t fieldNumber = tag >> 3;
        uint64_t wireType    = tag & 7;
        if (fieldNumber == 0)
            return;
        if (wireType == 0)
        {
            uint64_t ignored = 0;
            if (!ReadRawVarint(bytes, length, &offset, &ignored))
                return;
            continue;
        }
        if (wireType == 1)
        {
            if (length - offset < 8)
                return;
            offset += 8;
            continue;
        }
        if (wireType == 5)
        {
            if (length - offset < 4)
                return;
            offset += 4;
            continue;
        }
        if (wireType != 2)
            return;
        uint64_t valueLength = 0;
        if (!ReadRawVarint(bytes, length, &offset, &valueLength) || valueLength > length - offset)
            return;
        const uint8_t *valueBytes = bytes + offset;
        NSUInteger     valueSize  = (NSUInteger) valueLength;
        (*budget)--;
        if (fieldNumber == 36 || fieldNumber == 37)
        {
            if (IsPrintableRawData(valueBytes, valueSize))
            {
                NSString *value = [[NSString alloc] initWithBytes:valueBytes
                                                           length:valueSize
                                                         encoding:NSUTF8StringEncoding];
                RecordRawField(fields, fieldNumber == 36 ? @"title" : @"channel", value);
                RecordParsedText(fields, value);
            }
        }
        else if (IsPrintableRawData(valueBytes, valueSize))
        {
            NSString *value = [[NSString alloc] initWithBytes:valueBytes
                                                       length:valueSize
                                                     encoding:NSUTF8StringEncoding];
            RecordParsedText(fields, value);
        }
        else if (depth < 8 && valueSize <= 65536)
        {
            RecordRawMessage(fields, valueBytes, valueSize, depth + 1, budget);
        }
        offset += valueSize;
        if (fields[@"id"] && fields[@"title"] && fields[@"channel"])
            return;
    }
}

static void RecordRawExtensionFields(NSMutableDictionary *fields, const uint8_t *bytes,
                                     NSUInteger length)
{
    static const uint64_t path[]        = {172660663, 1, 168777401, 5, 232954548, 18};
    const uint8_t        *currentBytes  = bytes;
    NSUInteger            currentLength = length;
    for (NSUInteger pathIndex = 0; pathIndex < sizeof(path) / sizeof(path[0]); pathIndex++)
    {
        NSUInteger offset = 0;
        BOOL       found  = NO;
        while (offset < currentLength)
        {
            uint64_t tag = 0;
            if (!ReadRawVarint(currentBytes, currentLength, &offset, &tag))
                return;
            uint64_t fieldNumber = tag >> 3;
            uint64_t wireType    = tag & 7;
            if (wireType == 0)
            {
                uint64_t ignored = 0;
                if (!ReadRawVarint(currentBytes, currentLength, &offset, &ignored))
                    return;
                continue;
            }
            if (wireType == 1)
            {
                if (currentLength - offset < 8)
                    return;
                offset += 8;
                continue;
            }
            if (wireType == 5)
            {
                if (currentLength - offset < 4)
                    return;
                offset += 4;
                continue;
            }
            if (wireType != 2)
                return;
            uint64_t valueLength = 0;
            if (!ReadRawVarint(currentBytes, currentLength, &offset, &valueLength) ||
                valueLength > currentLength - offset)
                return;
            if (fieldNumber == path[pathIndex])
            {
                currentBytes  = currentBytes + offset;
                currentLength = (NSUInteger) valueLength;
                found         = YES;
                break;
            }
            offset += (NSUInteger) valueLength;
        }
        if (!found)
            return;
    }
    NSUInteger budget = 128;
    RecordRawMessage(fields, currentBytes, currentLength, 0, &budget);
}

static NSDictionary *RawRendererFields(NSData *data)
{
    if (![data isKindOfClass:[NSData class]] || data.length == 0)
        return nil;
    NSUInteger           limit      = MIN(data.length, (NSUInteger) 262144);
    const uint8_t       *bytes      = data.bytes;
    NSMutableDictionary *fields     = [NSMutableDictionary dictionaryWithCapacity:3];
    static const char   *prefixes[] = {"https://i.ytimg.com/vi/", "https://i.ytimg.com/vi_webp/"};
    for (NSUInteger index = 0; index < limit; index++)
    {
        for (NSUInteger prefixIndex = 0; prefixIndex < 2; prefixIndex++)
        {
            NSUInteger prefixLength = strlen(prefixes[prefixIndex]);
            if (index + prefixLength + 11 > limit ||
                memcmp(bytes + index, prefixes[prefixIndex], prefixLength) != 0)
                continue;
            NSString *identifier = [[NSString alloc] initWithBytes:bytes + index + prefixLength
                                                            length:11
                                                          encoding:NSUTF8StringEncoding];
            identifier           = ValidVideoID(identifier);
            if (identifier.length > 0)
                fields[@"id"] = identifier;
        }
    }
    RecordRawExtensionFields(fields, bytes, limit);
    if (!fields[@"title"] || !fields[@"channel"])
    {
        NSUInteger budget = 1024;
        RecordRawMessage(fields, bytes, limit, 0, &budget);
    }
    return fields.count > 0 ? fields.copy : nil;
}

static void RecordDirectObjectFields(id object, NSMutableDictionary *fields)
{
    if (!object)
        return;
    RecordParsedField(fields, @"id", IDFromContainer(object));
    RecordParsedField(fields, @"title", TitleFromContainer(object));
    RecordParsedField(fields, @"channel", ChannelFromContainer(object));

    if (!fields[@"id"])
        for (NSString *key in @[
                 @"videoId", @"videoID", @"videoIdentifier", @"contentVideoId", @"contentVideoID",
                 @"videoURL", @"watchURL", @"url", @"nodeModel", @"collectionElement",
                 @"strongComponent", @"weakComponent", @"owningReference", @"nodeContext"
             ])
            RecordParsedField(fields, @"id", VideoIDFromValue(ExplicitValue(object, key)));
    if (!fields[@"title"])
        for (NSString *key in @[
                 @"videoTitle", @"contentTitle", @"title", @"headline", @"titleText", @"nodeModel",
                 @"collectionElement", @"strongComponent", @"weakComponent", @"owningReference",
                 @"nodeContext"
             ])
            RecordParsedField(fields, @"title", TextFromValue(ExplicitValue(object, key)));
    if (!fields[@"channel"])
        for (NSString *key in @[
                 @"ownerDisplayName", @"ownerName", @"channelName", @"channelTitle", @"authorName",
                 @"channel", @"author", @"owner", @"shortBylineText", @"longBylineText",
                 @"nodeModel", @"collectionElement", @"strongComponent", @"weakComponent",
                 @"owningReference", @"nodeContext"
             ])
            RecordParsedField(fields, @"channel", TextFromValue(ExplicitValue(object, key)));

    if (!fields[@"title"] || !fields[@"channel"])
        for (NSString *key in
             @[ @"text", @"attributedText", @"currentTitle", @"accessibilityLabel" ])
            RecordParsedText(fields, TextFromValue(ExplicitValue(object, key)));
}

static NSCache<NSString *, VideoMetadataRecord *> *MetadataCache(void);

static NSMapTable *SourceMetadataCache(void)
{
    static NSMapTable     *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ cache = [NSMapTable weakToStrongObjectsMapTable]; });
    return cache;
}

static BOOL IsMetadataSource(id object)
{
    return object && ![object isKindOfClass:[NSData class]] &&
           ![object respondsToSelector:@selector(setElement:)] &&
           ![object respondsToSelector:@selector(didLoad)];
}

static VideoMetadataRecord *CachedSourceMetadata(id object)
{
    if (!IsMetadataSource(object))
        return nil;
    NSMapTable *cache = SourceMetadataCache();
    @synchronized(cache)
    {
        return [cache objectForKey:object];
    }
}

static void CacheSourceMetadata(id object, VideoMetadataRecord *metadata)
{
    if (!IsMetadataSource(object) || metadata.videoID.length == 0 || metadata.title.length == 0 ||
        metadata.channel.length == 0)
        return;
    NSMapTable *cache = SourceMetadataCache();
    @synchronized(cache)
    {
        [cache setObject:metadata forKey:object];
    }
}

static NSDictionary *DirectFieldsForContainer(id container)
{
    if (!container)
        return nil;
    NSMutableDictionary *fields = [NSMutableDictionary dictionaryWithCapacity:3];
    RecordDirectObjectFields(container, fields);
    NSDictionary *properties = ElementProperties(container);
    if (properties && properties != container)
        RecordDirectObjectFields(properties, fields);
    return fields.count > 0 ? fields.copy : nil;
}

static VideoMetadataRecord *RecordFromFields(NSDictionary *fields)
{
    NSString *videoID = fields[@"id"];
    if (!videoID.length)
        return nil;
    VideoMetadataRecord *cached  = [MetadataCache() objectForKey:videoID];
    NSString            *title   = fields[@"title"];
    NSString            *channel = fields[@"channel"];
    if (cached)
    {
        title   = title.length ? title : cached.title;
        channel = channel.length ? channel : cached.channel;
    }
    return [[VideoMetadataRecord alloc] initWithVideoID:videoID title:title channel:channel];
}

static VideoMetadataRecord *RecordFromContainers(NSArray *containers)
{
    VideoMetadataRecord *partial;
    for (id container in containers)
    {
        VideoMetadataRecord *cached = CachedSourceMetadata(container);
        if (cached)
            return cached;
        VideoMetadataRecord *record = RecordFromFields(DirectFieldsForContainer(container));
        if (!record)
            continue;
        if (record.videoID.length && record.title.length && record.channel.length)
        {
            CacheSourceMetadata(container, record);
            return record;
        }
        if (!partial)
            partial = record;
    }
    return partial;
}

static void AppendDirectObjectValues(NSMutableArray *containers, id object,
                                     NSArray<NSString *> *keys)
{
    if (!object || object == [NSNull null] || [object isKindOfClass:[NSString class]] ||
        [object isKindOfClass:[NSNumber class]])
        return;
    NSUInteger additions = 0;
    if (![containers containsObject:object])
    {
        [containers addObject:object];
        additions += 1;
    }
    for (NSString *key in keys)
    {
        if (additions >= 20 || containers.count >= 64)
            break;
        id value = ExplicitValue(object, key);
        if (!value || value == object || [value isKindOfClass:[NSString class]] ||
            [value isKindOfClass:[NSNumber class]])
            continue;
        if ([value isKindOfClass:[NSArray class]])
        {
            NSUInteger count = 0;
            for (id child in (NSArray *) value)
            {
                if (count++ >= 8 || additions >= 20 || containers.count >= 64)
                    break;
                if (child && child != object && child != [NSNull null] &&
                    ![child isKindOfClass:[NSString class]] &&
                    ![child isKindOfClass:[NSNumber class]])
                {
                    if (![containers containsObject:child])
                    {
                        [containers addObject:child];
                        additions += 1;
                    }
                }
            }
        }
        else
        {
            if (![containers containsObject:value])
            {
                [containers addObject:value];
                additions += 1;
            }
        }
    }
}

static dispatch_queue_t RawMetadataQueue(void)
{
    static dispatch_queue_t queue;
    static dispatch_once_t  onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("dev.adrian.dearrow.metadata", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static VideoMetadataRecord *RecordForSerializedData(NSData *serializedData)
{
    return serializedData ? RecordFromFields(RawRendererFields(serializedData)) : nil;
}

static BOOL NodeHasKnownClass(id node, NSArray<NSString *> *classNames)
{
    if (!node)
        return NO;
    for (Class current = object_getClass(node); current; current = class_getSuperclass(current))
    {
        if ([classNames containsObject:NSStringFromClass(current)])
            return YES;
    }
    return NO;
}

static NSData *SerializedRendererDataForEntry(id entry)
{
    if (!entry ||
        ![NSStringFromClass(object_getClass(entry)) isEqualToString:@"YTIElementRenderer"])
        return nil;
    id data = DirectObjectValue(entry, @"data");
    if (![data isKindOfClass:[NSData class]] || [(NSData *) data length] == 0 ||
        [(NSData *) data length] > 262144)
        return nil;
    return [data copy];
}

static NSCache<NSString *, VideoMetadataRecord *> *MetadataCache(void)
{
    static NSCache<NSString *, VideoMetadataRecord *> *cache;
    static dispatch_once_t                             onceToken;
    dispatch_once(&onceToken, ^{
        cache            = [NSCache new];
        cache.countLimit = 1024;
    });
    return cache;
}

static NSMapTable *NodeMetadataCache(void)
{
    static NSMapTable     *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ cache = [NSMapTable weakToStrongObjectsMapTable]; });
    return cache;
}

static VideoMetadataRecord *CacheRecord(VideoMetadataRecord *record)
{
    if (!record.videoID.length)
        return nil;
    VideoMetadataRecord *cached = [MetadataCache() objectForKey:record.videoID];
    if (cached)
    {
        NSString *title   = record.title.length ? record.title : cached.title;
        NSString *channel = record.channel.length ? record.channel : cached.channel;
        if (![title isEqualToString:record.title] || ![channel isEqualToString:record.channel])
            record = [[VideoMetadataRecord alloc] initWithVideoID:record.videoID
                                                            title:title
                                                          channel:channel];
    }
    [MetadataCache() setObject:record forKey:record.videoID];
    return record;
}

@implementation VideoMetadataAdapters

+ (VideoMetadataRecord *)recordForNode:(id)node
{
    if (!node)
        return nil;
    NSMapTable *nodeCache = NodeMetadataCache();
    @synchronized(nodeCache)
    {
        return [nodeCache objectForKey:node];
    }
}

+ (void)recordForNodeAsync:(id)node completion:(void (^)(VideoMetadataRecord *metadata))completion
{
    if (!completion)
        return;
    if (!node)
    {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        return;
    }
    if (![NSThread isMainThread])
    {
        dispatch_async(dispatch_get_main_queue(),
                       ^{ [self recordForNodeAsync:node completion:completion]; });
        return;
    }
    NSArray *knownClasses = @[
        @"YTShortsNode", @"YTShortsVideoNode", @"YTReelNode", @"YTReelItemNode", @"YTVideoNode",
        @"YTVideoWithContextNode", @"YTGridVideoNode", @"ELMCellNode"
    ];
    if (!NodeHasKnownClass(node, knownClasses))
    {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        return;
    }
    id weakNode = node;
    [self recordForEntryAsync:DirectObjectValue(node, @"entry")
                   completion:^(VideoMetadataRecord *metadata) {
                       if (metadata)
                       {
                           NSMapTable *nodeCache = NodeMetadataCache();
                           @synchronized(nodeCache)
                           {
                               [nodeCache setObject:metadata forKey:weakNode];
                           }
                       }
                       completion(metadata);
                   }];
}

+ (void)recordForEntryAsync:(id)entry completion:(void (^)(VideoMetadataRecord *metadata))completion
{
    if (!completion)
        return;
    if (!entry)
    {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        return;
    }
    VideoMetadataRecord *cached = CachedSourceMetadata(entry);
    if (cached)
    {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(cached); });
        return;
    }
    NSData *serializedData = SerializedRendererDataForEntry(entry);
    dispatch_async(RawMetadataQueue(), ^{
        VideoMetadataRecord *record = CacheRecord(RecordForSerializedData(serializedData));
        if (record)
            CacheSourceMetadata(entry, record);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(record); });
    });
}

+ (VideoMetadataRecord *)recordForElement:(id)element
{
    return CachedSourceMetadata(element);
}

+ (void)recordForElementAsync:(id)element
                   completion:(void (^)(VideoMetadataRecord *metadata))completion
{
    if (!completion)
        return;
    if (!element)
    {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        return;
    }
    if (![NSThread isMainThread])
    {
        dispatch_async(dispatch_get_main_queue(),
                       ^{ [self recordForElementAsync:element completion:completion]; });
        return;
    }
    dispatch_async(RawMetadataQueue(), ^{
        VideoMetadataRecord *record = CachedSourceMetadata(element);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(record); });
    });
}

+ (VideoMetadataRecord *)recordForObject:(id)object
{
    if (!object)
        return nil;
    NSMutableArray *containers = [NSMutableArray array];
    NSArray        *keys       = @[
        @"element",
        @"instance",
        @"context",
        @"controller",
        @"parentResponder",
        @"elementEntry",
        @"entry",
        @"cell",
        @"model",
        @"video",
        @"videoRenderer",
        @"videoWithContextRenderer",
        @"compactVideoRenderer",
        @"shortsVideoRenderer",
        @"reelItemRenderer",
        @"navigationEndpoint",
        @"watchEndpoint",
        @"contentModel",
        @"currentVideo",
        @"contentVideo",
        @"activeVideo",
        @"response",
        @"watchNextResponse",
        @"watchResponse",
        @"playbackData",
        @"contentPlaybackData",
        @"data",
        @"properties",
        @"allProperties",
        @"renderer",
        @"videoDetails",
        @"videoData",
        @"metadata",
        @"subnodes",
        @"text",
        @"attributedText",
        @"accessibilityLabel",
        @"accessibilityIdentifier",
        @"singleVideoController",
        @"singleVideo",
        @"watchController",
        @"videoController",
        @"player",
        @"contentView",
        @"parentController",
        @"asyncdisplaykit_node",
        @"displayNode",
        @"node",
        @"cellNode",
        @"representedObject",
        @"sectionController",
        @"item"
    ];
    [containers removeAllObjects];
    AppendDirectObjectValues(containers, object, keys);
    return CacheRecord(RecordFromContainers(containers));
}

+ (NSString *)videoIDFromURL:(id)value
{
    return VideoIDFromURLObject(value);
}

+ (void)invalidateNode:(id)node
{
    if (!node)
        return;
    NSMapTable *nodeCache = NodeMetadataCache();
    @synchronized(nodeCache)
    {
        [nodeCache removeObjectForKey:node];
    }
}

@end
