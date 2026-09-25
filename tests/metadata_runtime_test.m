#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#import "Metadata.h"

@interface ELMElement : NSObject

- (const void *)instance;

@end

@implementation ELMElement

- (const void *)instance
{
    return (const void *) (uintptr_t) 1;
}

@end

@interface YTIElementRenderer : NSObject

@property (nonatomic, copy) NSData *data;

@end

@implementation YTIElementRenderer
@end

@interface YTVideoWithContextNode : NSObject

@property (nonatomic, strong) ELMElement         *element;
@property (nonatomic, strong) YTIElementRenderer *entry;

@end

@implementation YTVideoWithContextNode
@end

@interface YTUnknownVideoNode : NSObject

@property (nonatomic, strong) ELMElement         *element;
@property (nonatomic, strong) YTIElementRenderer *entry;

@end

@implementation YTUnknownVideoNode
@end

static void AppendVarint(NSMutableData *data, uint64_t value)
{
    while (value >= 0x80)
    {
        uint8_t byte = (uint8_t) ((value & 0x7f) | 0x80);
        [data appendBytes:&byte length:1];
        value >>= 7;
    }
    uint8_t byte = (uint8_t) value;
    [data appendBytes:&byte length:1];
}

static NSData *LengthDelimitedField(uint64_t field, NSData *value)
{
    NSMutableData *data = [NSMutableData data];
    AppendVarint(data, (field << 3) | 2);
    AppendVarint(data, value.length);
    [data appendData:value];
    return data;
}

static NSData *SerializedRenderer(NSString *videoID, NSString *title, NSString *channel)
{
    NSMutableData *renderer = [NSMutableData data];
    NSString      *thumbnailURL =
        [NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/hqdefault.jpg", videoID];
    [renderer
        appendData:LengthDelimitedField(1, [thumbnailURL dataUsingEncoding:NSUTF8StringEncoding])];
    [renderer appendData:LengthDelimitedField(36, [title dataUsingEncoding:NSUTF8StringEncoding])];
    [renderer
        appendData:LengthDelimitedField(37, [channel dataUsingEncoding:NSUTF8StringEncoding])];

    NSData *nested = LengthDelimitedField(18, renderer);
    nested         = LengthDelimitedField(232954548, nested);
    nested         = LengthDelimitedField(5, nested);
    nested         = LengthDelimitedField(168777401, nested);
    nested         = LengthDelimitedField(1, nested);
    nested         = LengthDelimitedField(172660663, nested);
    return nested;
}

static int VerifyNodeMetadata(NSString *videoID, NSString *title, NSString *channel)
{
    YTIElementRenderer *entry              = [YTIElementRenderer new];
    entry.data                             = SerializedRenderer(videoID, title, channel);
    YTVideoWithContextNode *node           = [YTVideoWithContextNode new];
    node.entry                             = entry;
    __block BOOL                 completed = NO;
    __block VideoMetadataRecord *record;
    [VideoMetadataAdapters recordForNodeAsync:node
                                   completion:^(VideoMetadataRecord *metadata) {
                                       record    = metadata;
                                       completed = YES;
                                       CFRunLoopStop(CFRunLoopGetMain());
                                   }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
    while (!completed && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    if (!completed)
    {
        fprintf(stderr, "metadata completion timed out\n");
        return 1;
    }
    if (![record.videoID isEqualToString:videoID] || ![record.title isEqualToString:title] ||
        ![record.channel isEqualToString:channel])
    {
        fprintf(stderr, "unexpected metadata: id=%s title=%s channel=%s\n",
                record.videoID.UTF8String ?: "", record.title.UTF8String ?: "",
                record.channel.UTF8String ?: "");
        return 1;
    }
    if ([VideoMetadataAdapters recordForNode:node] != record)
    {
        fprintf(stderr, "node metadata was not cached\n");
        return 1;
    }
    return 0;
}

static int VerifyOpaqueElementIsIgnored(void)
{
    ELMElement                  *element   = [ELMElement new];
    __block BOOL                 completed = NO;
    __block VideoMetadataRecord *record;
    [VideoMetadataAdapters recordForElementAsync:element
                                      completion:^(VideoMetadataRecord *metadata) {
                                          record    = metadata;
                                          completed = YES;
                                          CFRunLoopStop(CFRunLoopGetMain());
                                      }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
    while (!completed && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    if (!completed || record)
    {
        fprintf(stderr, "opaque Elements pointers must remain uninspected\n");
        return 1;
    }
    return 0;
}

static int VerifyUnknownNodeIsIgnored(void)
{
    YTIElementRenderer *entry = [YTIElementRenderer new];
    entry.data                = SerializedRenderer(@"pi-IO4laax4", @"Unknown", @"Unknown");
    YTUnknownVideoNode *node  = [YTUnknownVideoNode new];
    node.entry                = entry;
    __block BOOL                 completed = NO;
    __block VideoMetadataRecord *record;
    [VideoMetadataAdapters recordForNodeAsync:node
                                   completion:^(VideoMetadataRecord *metadata) {
                                       record    = metadata;
                                       completed = YES;
                                       CFRunLoopStop(CFRunLoopGetMain());
                                   }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
    while (!completed && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    if (!completed || record)
    {
        fprintf(stderr, "unknown node classes must remain unclassified\n");
        return 1;
    }
    return 0;
}

static int RunMetadataTest(void)
{
    int firstResult = VerifyNodeMetadata(
        @"4hfzKaa6fSk", @"Cop goes crazy over person driving Power Wheels", @"Penguinz0");
    if (firstResult != 0)
        return firstResult;

    int secondResult =
        VerifyNodeMetadata(@"pi-IO4laax4", @"These Are Some Wild Bodycams", @"penguinz0");
    if (secondResult != 0)
        return secondResult;

    int opaqueResult = VerifyOpaqueElementIsIgnored();
    if (opaqueResult != 0)
        return opaqueResult;

    int unknownResult = VerifyUnknownNodeIsIgnored();
    if (unknownResult != 0)
        return unknownResult;

    puts("video renderer metadata and opaque pointer safety passed");
    return 0;
}

int main(void)
{
    @autoreleasepool
    {
        return RunMetadataTest();
    }
}
