#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VideoMetadataRecord : NSObject <NSCopying>

@property (nonatomic, copy, readonly) NSString           *videoID;
@property (nonatomic, copy, readonly, nullable) NSString *title;
@property (nonatomic, copy, readonly, nullable) NSString *channel;

- (instancetype)initWithVideoID:(NSString *)videoID
                          title:(nullable NSString *)title
                        channel:(nullable NSString *)channel;

@end

@interface VideoMetadataAdapters : NSObject

+ (VideoMetadataRecord *_Nullable)recordForNode:(id)node;
+ (VideoMetadataRecord *_Nullable)recordForObject:(id)object;
+ (NSString *_Nullable)videoIDFromURL:(id)URL;

@end

NS_ASSUME_NONNULL_END
