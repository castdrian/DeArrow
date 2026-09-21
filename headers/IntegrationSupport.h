#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "Metadata.h"

@class BrandingRequestToken;

@interface                                                    BrandingBinding : NSObject
@property (nonatomic, strong, nullable) VideoMetadataRecord  *metadata;
@property (nonatomic, strong, nullable) BrandingRequestToken *brandingToken;
@property (nonatomic, strong, nullable) BrandingRequestToken *thumbnailBrandingToken;
@property (nonatomic, strong, nullable) BrandingRequestToken *thumbnailToken;
@property (nonatomic, copy, nullable) NSAttributedString     *originalTitle;
@property (nonatomic, strong, nullable) UIImage              *originalImage;
@property (nonatomic) NSUInteger                              generation;
@property (nonatomic) BOOL                                    metadataAttempted;
@property (nonatomic) BOOL                                    brandingResolved;
@property (nonatomic) BOOL                                    thumbnailBrandingResolved;
@property (nonatomic) BOOL                                    thumbnailResolved;
@property (nonatomic) NSTimeInterval                          brandingRetryTime;
@property (nonatomic) NSTimeInterval                          thumbnailBrandingRetryTime;
@property (nonatomic) NSTimeInterval                          thumbnailRetryTime;
@property (nonatomic) BOOL                                    applyingTitle;
@property (nonatomic) BOOL                                    applyingThumbnail;
@end

BrandingBinding     *DeArrowBindingForObject(id object, BOOL create);
VideoMetadataRecord *DeArrowStoredMetadataForObject(id object);
void                 DeArrowAssociateMetadata(id object, VideoMetadataRecord *metadata);
void                 DeArrowAssociateVideoID(id object, NSString *videoID);
void                 DeArrowCancelBinding(id object);
void                 DeArrowResetBindingForReuse(id object);
void                 DeArrowRegisterTitleObject(id object);
void                 DeArrowRefreshTitleObjects(void);
void                 DeArrowRegisterThumbnailObject(id object);
void                 DeArrowRefreshThumbnailObjects(void);
