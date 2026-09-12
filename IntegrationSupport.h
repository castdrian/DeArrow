#import <Foundation/Foundation.h>

#import "Metadata.h"

@class BrandingRequestToken;

@interface BrandingBinding : NSObject
@property(nonatomic, strong, nullable) VideoMetadataRecord *metadata;
@property(nonatomic, strong, nullable) BrandingRequestToken *brandingToken;
@property(nonatomic, strong, nullable) BrandingRequestToken *thumbnailBrandingToken;
@property(nonatomic, strong, nullable) BrandingRequestToken *thumbnailToken;
@property(nonatomic, copy, nullable) NSAttributedString *originalTitle;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL metadataAttempted;
@property(nonatomic) BOOL applyingTitle;
@property(nonatomic) BOOL applyingThumbnail;
@property(nonatomic) BOOL relatedViewsBound;
@end

BrandingBinding *DeArrowBindingForObject(id object, BOOL create);
VideoMetadataRecord *DeArrowStoredMetadataForObject(id object);
VideoMetadataRecord *DeArrowMetadataForObject(id object);
void DeArrowAssociateMetadata(id object, VideoMetadataRecord *metadata);
void DeArrowAssociateVideoID(id object, NSString *videoID);
void DeArrowPropagateMetadata(id parent, id child);
VideoMetadataRecord *DeArrowMetadataFromParents(id object);
void DeArrowCancelBinding(id object);
void DeArrowRegisterTitleObject(id object);
void DeArrowRefreshTitleObjects(void);
