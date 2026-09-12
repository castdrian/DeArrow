#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "BrandingRecord.h"

NS_ASSUME_NONNULL_BEGIN

@interface BrandingRequestToken : NSObject
- (void)cancel;
@end

typedef void (^BrandingCompletion)(BrandingRecord * _Nullable record, NSError * _Nullable error);
typedef void (^ThumbnailCompletion)(UIImage * _Nullable image, NSError * _Nullable error);

@interface BrandingClient : NSObject

+ (instancetype)sharedClient;
- (BrandingRecord * _Nullable)cachedBrandingForVideoID:(NSString *)videoID;
- (BrandingRequestToken *)requestBrandingForVideoID:(NSString *)videoID
                                         completion:(BrandingCompletion)completion;
- (BrandingRequestToken *)requestThumbnailForVideoID:(NSString *)videoID
                                           completion:(ThumbnailCompletion)completion;
- (void)clearCache;

@end

NS_ASSUME_NONNULL_END
