#import "BrandingRecord.h"

@implementation BrandingRecord

- (instancetype)initWithVideoID:(NSString *)videoID
                           title:(NSString *)title
                    thumbnailURL:(NSURL *)thumbnailURL {
    self = [super init];
    if (self) {
        _videoID = [videoID copy];
        _title = [title copy];
        _thumbnailURL = [thumbnailURL copy];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end
