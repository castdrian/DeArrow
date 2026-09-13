#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrandingRecord : NSObject <NSCopying>

@property (nonatomic, copy, readonly) NSString           *videoID;
@property (nonatomic, copy, readonly, nullable) NSString *title;
@property (nonatomic, copy, readonly, nullable) NSURL    *thumbnailURL;

- (instancetype)initWithVideoID:(NSString *)videoID
                          title:(nullable NSString *)title
                   thumbnailURL:(nullable NSURL *)thumbnailURL;

@end

NS_ASSUME_NONNULL_END
