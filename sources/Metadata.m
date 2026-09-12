#import "Metadata.h"

@implementation VideoMetadataRecord

- (instancetype)initWithVideoID:(NSString *)videoID
                           title:(NSString *)title
                         channel:(NSString *)channel {
    self = [super init];
    if (self) {
        _videoID = [videoID copy];
        _title = [title copy];
        _channel = [channel copy];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end

static NSString *ValidVideoID(NSString *value) {
    if (![value isKindOfClass:[NSString class]] || value.length != 11)
        return nil;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
    if ([value rangeOfCharacterFromSet:[allowed invertedSet]].location != NSNotFound)
        return nil;
    return value;
}

static id ExplicitValue(id object, NSString *key) {
    if (!object || key.length == 0 || object == [NSNull null])
        return nil;
    if ([object isKindOfClass:[NSDictionary class]])
        return [(NSDictionary *)object objectForKey:key];
    SEL selector = NSSelectorFromString(key);
    if (![object respondsToSelector:selector])
        return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *TextFromValue(id value) {
    if ([value isKindOfClass:[NSString class]])
        return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSString *simpleText = TextFromValue(value[@"simpleText"]);
        if (simpleText.length > 0)
            return simpleText;
        NSArray *runs = value[@"runs"];
        if ([runs isKindOfClass:[NSArray class]]) {
            NSMutableString *text = [NSMutableString string];
            for (id run in runs) {
                NSString *runText = TextFromValue([run isKindOfClass:[NSDictionary class]] ? run[@"text"] : nil);
                if (runText.length > 0)
                    [text appendString:runText];
            }
            return text.length > 0 ? text : nil;
        }
    }
    return nil;
}

static NSString *ValueFromKeys(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        NSString *value = TextFromValue(ExplicitValue(object, key));
        if (value.length > 0)
            return value;
    }
    return nil;
}

static NSString *VideoIDFromValue(id value) {
    NSString *direct = ValidVideoID(TextFromValue(value));
    if (direct)
        return direct;
    NSArray<NSString *> *keys = @[@"videoId", @"videoID", @"video_id", @"videoIdentifier", @"contentVideoID", @"contentVideoId", @"identifier", @"id", @"currentVideoID", @"currentVideoId"];
    for (NSString *key in keys) {
        NSString *candidate = ValidVideoID(TextFromValue(ExplicitValue(value, key)));
        if (candidate)
            return candidate;
    }
    return nil;
}

static NSString *IDFromContainer(id container) {
    NSString *videoID = VideoIDFromValue(container);
    if (videoID)
        return videoID;
    for (NSString *key in @[@"video", @"videoRenderer", @"compactVideoRenderer", @"richItemRenderer", @"navigationEndpoint", @"watchEndpoint", @"command", @"model"]) {
        videoID = VideoIDFromValue(ExplicitValue(container, key));
        if (videoID)
            return videoID;
    }
    return nil;
}

static NSString *TitleFromContainer(id container) {
    NSString *title = ValueFromKeys(container, @[@"title", @"videoTitle", @"headline", @"titleText", @"displayTitle"]);
    if (title.length > 0)
        return title;
    for (NSString *key in @[@"video", @"videoRenderer", @"compactVideoRenderer", @"model"]) {
        title = ValueFromKeys(ExplicitValue(container, key), @[@"title", @"videoTitle", @"headline", @"titleText"]);
        if (title.length > 0)
            return title;
    }
    return nil;
}

static NSString *ChannelFromContainer(id container) {
    NSString *channel = ValueFromKeys(container, @[@"channelName", @"channelTitle", @"ownerName", @"author", @"owner", @"shortBylineText", @"longBylineText"]);
    if (channel.length > 0)
        return channel;
    for (NSString *key in @[@"video", @"videoRenderer", @"compactVideoRenderer", @"model"]) {
        channel = ValueFromKeys(ExplicitValue(container, key), @[@"channelName", @"channelTitle", @"ownerName", @"author", @"owner", @"shortBylineText", @"longBylineText"]);
        if (channel.length > 0)
            return channel;
    }
    return nil;
}

static NSDictionary *ElementProperties(id element) {
    if (!element)
        return nil;
    for (NSString *key in @[@"allProperties", @"properties", @"data"]) {
        id value = ExplicitValue(element, key);
        if ([value isKindOfClass:[NSDictionary class]])
            return value;
    }
    return nil;
}

static VideoMetadataRecord *RecordFromContainers(NSArray *containers) {
    NSString *videoID;
    NSString *title;
    NSString *channel;
    for (id container in containers) {
        if (!videoID)
            videoID = IDFromContainer(container);
        if (!title)
            title = TitleFromContainer(container);
        if (!channel)
            channel = ChannelFromContainer(container);
        NSDictionary *properties = ElementProperties(container);
        if (properties) {
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

@implementation VideoMetadataAdapters

+ (VideoMetadataRecord *)recordForNode:(id)node {
    if (!node)
        return nil;
    NSString *className = NSStringFromClass([node class]);
    if (![className containsString:@"YTVideoNode"] &&
        ![className containsString:@"YTGridVideoNode"] &&
        ![className containsString:@"Short"] &&
        ![className containsString:@"Reel"] &&
        ![className containsString:@"ELMCellNode"])
        return [self recordForObject:node];

    NSMutableArray *containers = [NSMutableArray arrayWithObject:node];
    for (NSString *key in @[@"element", @"model", @"video", @"videoRenderer", @"contentModel", @"currentVideo", @"response", @"data"]) {
        id value = ExplicitValue(node, key);
        if (value)
            [containers addObject:value];
    }
    return RecordFromContainers(containers);
}

+ (VideoMetadataRecord *)recordForObject:(id)object {
    if (!object)
        return nil;
    NSMutableArray *containers = [NSMutableArray arrayWithObject:object];
    for (NSString *key in @[@"element", @"model", @"video", @"videoRenderer", @"navigationEndpoint", @"watchEndpoint", @"contentModel", @"currentVideo", @"data"]) {
        id value = ExplicitValue(object, key);
        if (value)
            [containers addObject:value];
    }
    return RecordFromContainers(containers);
}

+ (NSString *)videoIDFromURL:(id)value {
    NSURL *URL = [value isKindOfClass:[NSURL class]] ? value : [NSURL URLWithString:TextFromValue(value) ?: @""];
    if (!URL)
        return nil;
    NSURLComponents *components = [NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"v"] || [item.name isEqualToString:@"videoID"] || [item.name isEqualToString:@"video_id"]) {
            NSString *candidate = ValidVideoID(item.value);
            if (candidate)
                return candidate;
        }
    }
    NSArray *parts = [URL.path componentsSeparatedByString:@"/"];
    for (NSUInteger index = 0; index + 1 < parts.count; index++) {
        if ([parts[index] isEqualToString:@"vi"] || [parts[index] isEqualToString:@"vi_webp"] || [parts[index] isEqualToString:@"embed"]) {
            NSString *candidate = ValidVideoID(parts[index + 1]);
            if (candidate)
                return candidate;
        }
    }
    if ([URL.host.lowercaseString isEqualToString:@"youtu.be"]) {
        for (NSInteger index = (NSInteger)parts.count - 1; index >= 0; index--) {
            NSString *candidate = ValidVideoID(parts[(NSUInteger)index]);
            if (candidate)
                return candidate;
        }
    }
    return nil;
}

@end
