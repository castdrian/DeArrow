#import "Metadata.h"

#import <objc/runtime.h>

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

static id ExplicitValue(id object, NSString *key)
{
    if (!object || key.length == 0 || object == [NSNull null])
        return nil;
    if ([object isKindOfClass:[NSDictionary class]])
        return [(NSDictionary *) object objectForKey:key];
    SEL selector = NSSelectorFromString(key);
    if (![object respondsToSelector:selector])
        return nil;
    @try
    {
        return [object valueForKey:key];
    }
    @catch (__unused NSException *exception)
    {
        return nil;
    }
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
        @"contentVideoId", @"identifier", @"id", @"currentVideoID", @"currentVideoId"
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
             @"video", @"videoRenderer", @"videoWithContextRenderer", @"compactVideoRenderer",
             @"shortsVideoRenderer", @"reelItemRenderer", @"richItemRenderer",
             @"navigationEndpoint", @"watchEndpoint", @"command", @"model"
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
    NSString *title = ValueFromKeys(
        container, @[ @"title", @"videoTitle", @"headline", @"titleText", @"displayTitle" ]);
    if (title.length > 0)
        return title;
    for (NSString *key in @[
             @"video", @"videoRenderer", @"videoWithContextRenderer", @"compactVideoRenderer",
             @"shortsVideoRenderer", @"reelItemRenderer", @"model"
         ])
    {
        title = ValueFromKeys(ExplicitValue(container, key),
                              @[ @"title", @"videoTitle", @"headline", @"titleText" ]);
        if (title.length > 0)
            return title;
    }
    return nil;
}

static NSString *ChannelFromContainer(id container)
{
    NSString *channel = ValueFromKeys(container, @[
        @"channelName", @"channelTitle", @"ownerName", @"author", @"owner", @"shortBylineText",
        @"longBylineText"
    ]);
    if (channel.length > 0)
        return channel;
    for (NSString *key in @[
             @"video", @"videoRenderer", @"videoWithContextRenderer", @"compactVideoRenderer",
             @"shortsVideoRenderer", @"reelItemRenderer", @"model"
         ])
    {
        channel = ValueFromKeys(ExplicitValue(container, key), @[
            @"channelName", @"channelTitle", @"ownerName", @"author", @"owner", @"shortBylineText",
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

static VideoMetadataRecord *RecordFromContainers(NSArray *containers)
{
    NSString *videoID;
    NSString *title;
    NSString *channel;
    for (id container in containers)
    {
        if (!videoID)
            videoID = IDFromContainer(container);
        if (!title)
            title = TitleFromContainer(container);
        if (!channel)
            channel = ChannelFromContainer(container);
        NSDictionary *properties = ElementProperties(container);
        if (properties)
        {
            if (!videoID)
                videoID = IDFromContainer(properties);
            if (!title)
                title = TitleFromContainer(properties);
            if (!channel)
                channel = ChannelFromContainer(properties);
        }
        if (videoID && title && channel)
            break;
    }
    if (!videoID)
        return nil;
    return [[VideoMetadataRecord alloc] initWithVideoID:videoID title:title channel:channel];
}

static void AppendContainer(NSMutableArray *containers, id value)
{
    if (value)
        [containers addObject:value];
}

static VideoMetadataRecord *RecordForElementsNode(id node)
{
    NSMutableArray *containers = [NSMutableArray arrayWithObject:node];
    for (NSString *key in
         @[ @"element", @"model", @"contentModel", @"data", @"properties", @"allProperties" ])
        AppendContainer(containers, ExplicitValue(node, key));
    return RecordFromContainers(containers);
}

static VideoMetadataRecord *RecordForShortsNode(id node)
{
    NSMutableArray *containers = [NSMutableArray arrayWithObject:node];
    for (NSString *key in @[
             @"shortsVideoRenderer", @"reelItemRenderer", @"video", @"videoRenderer", @"model",
             @"contentModel", @"navigationEndpoint"
         ])
        AppendContainer(containers, ExplicitValue(node, key));
    return RecordFromContainers(containers);
}

static VideoMetadataRecord *RecordForYouTubeVideoNode(id node)
{
    NSMutableArray *containers = [NSMutableArray arrayWithObject:node];
    for (NSString *key in @[
             @"video", @"videoRenderer", @"videoWithContextRenderer", @"compactVideoRenderer",
             @"model", @"contentModel", @"currentVideo", @"response", @"data"
         ])
        AppendContainer(containers, ExplicitValue(node, key));
    return RecordFromContainers(containers);
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
    if (NodeHasKnownClass(node, @[ @"ELMCellNode" ]))
        return CacheRecord(RecordForElementsNode(node));
    if (NodeHasKnownClass(
            node, @[ @"YTShortsNode", @"YTShortsVideoNode", @"YTReelNode", @"YTReelItemNode" ]))
        return CacheRecord(RecordForShortsNode(node));
    if (NodeHasKnownClass(node, @[ @"YTVideoNode", @"YTVideoWithContextNode", @"YTGridVideoNode" ]))
        return CacheRecord(RecordForYouTubeVideoNode(node));
    return nil;
}

+ (VideoMetadataRecord *)recordForObject:(id)object
{
    if (!object)
        return nil;
    NSMutableArray *containers = [NSMutableArray arrayWithObject:object];
    for (NSString *key in @[
             @"element", @"model", @"video", @"videoRenderer", @"videoWithContextRenderer",
             @"compactVideoRenderer", @"shortsVideoRenderer", @"reelItemRenderer",
             @"navigationEndpoint", @"watchEndpoint", @"contentModel", @"currentVideo", @"data"
         ])
        AppendContainer(containers, ExplicitValue(object, key));
    return CacheRecord(RecordFromContainers(containers));
}

+ (NSString *)videoIDFromURL:(id)value
{
    return VideoIDFromURLObject(value);
}

@end
