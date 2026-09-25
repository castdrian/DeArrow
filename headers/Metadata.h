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
+ (void)recordForNodeAsync:(id)node
                completion:(void (^)(VideoMetadataRecord *_Nullable metadata))completion;
+ (void)recordForEntryAsync:(id)entry
                 completion:(void (^)(VideoMetadataRecord *_Nullable metadata))completion;
+ (VideoMetadataRecord *_Nullable)recordForElement:(id)element;
+ (void)recordForElementAsync:(id)element
                   completion:(void (^)(VideoMetadataRecord *_Nullable metadata))completion;
+ (VideoMetadataRecord *_Nullable)recordForObject:(id)object;
+ (NSString *_Nullable)videoIDFromURL:(id)URL;
+ (void)invalidateNode:(id)node;

@end

NS_ASSUME_NONNULL_END
