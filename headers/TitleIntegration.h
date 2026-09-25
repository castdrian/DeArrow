#import <Foundation/Foundation.h>

@class VideoMetadataRecord;

void DeArrowInstallPlayerIntegration(void);
void DeArrowInstallTitleIntegration(void);
void DeArrowCaptureTitleTextObject(id object);
void DeArrowCaptureTitleObject(id object, VideoMetadataRecord *metadata);
void DeArrowRememberUnresolvedTitleObject(id object, NSString *text);
void DeArrowResolveTitleObjectsForMetadata(VideoMetadataRecord *metadata);
void DeArrowRefreshTitleObject(id object);
