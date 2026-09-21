#import "ThumbnailIntegration.h"

#import <objc/runtime.h>

#import "BrandingClient.h"
#import "HookSupport.h"
#import "IntegrationSupport.h"
#import "Metadata.h"
#import "Preferences.h"

static BOOL HasMethodArguments(Class targetClass, SEL selector, unsigned int count)
{
    Method method = targetClass ? class_getInstanceMethod(targetClass, selector) : NULL;
    return method && method_getNumberOfArguments(method) == count;
}

static BOOL IsLikelyVideoThumbnail(UIImage *image)
{
    if (!image)
        return NO;
    CGFloat width  = image.size.width;
    CGFloat height = image.size.height;
    if (width < 80.0 || height < 40.0)
        return NO;
    CGFloat larger  = MAX(width, height);
    CGFloat smaller = MIN(width, height);
    return smaller > 0.0 && larger / smaller >= 1.25;
}

static void ApplyThumbnailToObject(id object, BOOL animated)
{
    if (!object || [DeArrowPreferences sharedPreferences].isEnabled == NO ||
        [DeArrowPreferences sharedPreferences].replaceThumbnails == NO)
        return;
    VideoMetadataRecord *metadata = DeArrowStoredMetadataForObject(object);
    if (!metadata || !metadata.videoID.length)
        return;
    BrandingBinding *binding = DeArrowBindingForObject(object, YES);
    DeArrowRegisterThumbnailObject(object);
    if (!binding.metadata || ![binding.metadata.videoID isEqualToString:metadata.videoID])
        DeArrowAssociateMetadata(object, metadata);
    binding = DeArrowBindingForObject(object, YES);
    if (binding.thumbnailBrandingToken || binding.thumbnailBrandingResolved ||
        binding.thumbnailBrandingRetryTime > [NSDate date].timeIntervalSince1970)
        return;
    NSString               *videoID     = metadata.videoID;
    NSUInteger              generation  = binding.generation;
    __weak id               weakObject  = object;
    __weak BrandingBinding *weakBinding = binding;
    binding.thumbnailBrandingToken      = [[BrandingClient sharedClient]
        requestBrandingForVideoID:videoID
                       completion:^(BrandingRecord *record, NSError *error) {
                           id               strongObject  = weakObject;
                           BrandingBinding *strongBinding = weakBinding;
                           if (!strongObject || !strongBinding ||
                               strongBinding.generation != generation ||
                               ![strongBinding.metadata.videoID isEqualToString:videoID])
                               return;
                           strongBinding.thumbnailBrandingToken    = nil;
                           strongBinding.thumbnailBrandingResolved = error == nil;
                           strongBinding.thumbnailBrandingRetryTime =
                               error ? [NSDate date].timeIntervalSince1970 + 10.0 : 0.0;
                           if (!record.thumbnailURL)
                               return;
                           if (![DeArrowPreferences sharedPreferences].isEnabled ||
                               ![DeArrowPreferences sharedPreferences].replaceThumbnails)
                               return;
                           if (strongBinding.thumbnailToken || strongBinding.thumbnailResolved ||
                               strongBinding.thumbnailRetryTime >
                                   [NSDate date].timeIntervalSince1970)
                               return;
                           strongBinding.thumbnailToken = [[BrandingClient sharedClient]
                               requestThumbnailForVideoID:videoID
                                               completion:^(UIImage *image,
                                                            NSError *thumbnailError) {
                                                   id               currentObject  = weakObject;
                                                   BrandingBinding *currentBinding = weakBinding;
                                                   if (!currentObject || !currentBinding ||
                                                       currentBinding.generation != generation ||
                                                       ![currentBinding.metadata.videoID
                                                           isEqualToString:videoID])
                                                       return;
                                                   currentBinding.thumbnailToken = nil;
                                                   currentBinding.thumbnailResolved =
                                                       image != nil && thumbnailError == nil;
                                                   currentBinding.thumbnailRetryTime =
                                                       currentBinding.thumbnailResolved
                                                           ? 0.0
                                                           : [NSDate date].timeIntervalSince1970 +
                                                                 10.0;
                                                   if (!image)
                                                       return;
                                                   if (currentBinding.applyingThumbnail)
                                                       return;
                                                   currentBinding.applyingThumbnail = YES;
                                                   [currentObject setImage:image];
                                                   currentBinding.applyingThumbnail = NO;
                                               }];
                       }];
    if (animated)
        [object setNeedsLayout];
}

void DeArrowRefreshThumbnailObject(id object)
{
    if (!object)
        return;
    BrandingBinding *binding = DeArrowBindingForObject(object, NO);
    if (!binding)
        return;
    DeArrowPreferences *preferences = [DeArrowPreferences sharedPreferences];
    if (!preferences.isEnabled || !preferences.replaceThumbnails)
    {
        [binding.thumbnailBrandingToken cancel];
        [binding.thumbnailToken cancel];
        binding.thumbnailBrandingToken     = nil;
        binding.thumbnailToken             = nil;
        binding.thumbnailBrandingResolved  = NO;
        binding.thumbnailResolved          = NO;
        binding.thumbnailBrandingRetryTime = 0.0;
        binding.thumbnailRetryTime         = 0.0;
        if (binding.originalImage && !binding.applyingThumbnail)
        {
            binding.applyingThumbnail = YES;
            [object setImage:binding.originalImage];
            binding.applyingThumbnail = NO;
        }
        return;
    }
    ApplyThumbnailToObject(object, NO);
}

static void InstallImageSetter(Class targetClass)
{
    SEL selector = @selector(setImage:);
    if (!HasMethodArguments(targetClass, selector, 3))
        return;
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^(id object, SEL selector, UIImage *image) {
            BrandingBinding *binding = DeArrowBindingForObject(object, NO);
            ((void (*)(id, SEL, UIImage *)) original)(object, selector, image);
            if (binding && binding.applyingThumbnail)
                return;
            binding = DeArrowBindingForObject(object, NO);
            if (!binding || !IsLikelyVideoThumbnail(image))
                return;
            binding.originalImage = image;
            ApplyThumbnailToObject(object, NO);
        };
    });
}

void DeArrowInstallThumbnailIntegration(void)
{
    Class imageNodeClass = NSClassFromString(@"ASImageNode");
    if (!imageNodeClass)
        return;
    InstallImageSetter(imageNodeClass);
}
