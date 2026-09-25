#import "ThumbnailIntegration.h"

#import <objc/runtime.h>

#import "BrandingClient.h"
#import "HookSupport.h"
#import "ImageSetterSupport.h"
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

static void ApplyReplacementImage(id object, BrandingBinding *binding)
{
    UIImage *replacementImage = binding.replacementImage;
    if (!object || !replacementImage || binding.applyingThumbnail)
        return;
    id currentImage = [object respondsToSelector:@selector(image)] ? [object image] : nil;
    if (currentImage == replacementImage)
        return;
    binding.applyingThumbnail = YES;
    @try
    {
        [object setImage:replacementImage];
    }
    @finally
    {
        binding.applyingThumbnail = NO;
    }
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
    if (binding.replacementImage)
    {
        ApplyReplacementImage(object, binding);
        return;
    }
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
                                                   currentBinding.replacementImage  = image;
                                                   currentBinding.applyingThumbnail = YES;
                                                   @try
                                                   {
                                                       [currentObject setImage:image];
                                                   }
                                                   @finally
                                                   {
                                                       currentBinding.applyingThumbnail = NO;
                                                   }
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
        binding.replacementImage           = nil;
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

static BOOL InstallImageSetter(Class targetClass)
{
    SEL selector = @selector(setImage:);
    if (!HasMethodArguments(targetClass, selector, 3))
        return NO;
    return DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^(id object, UIImage *image) {
            BrandingBinding *binding = DeArrowBindingForObject(object, NO);
            if (binding && binding.applyingThumbnail)
            {
                DeArrowInvokeImageSetterWithReplacement(object, command, original, image, nil);
                return;
            }
            binding = DeArrowBindingForObject(object, NO);
            if (!binding)
            {
                DeArrowInvokeImageSetterWithReplacement(object, command, original, image, nil);
                return;
            }
            if (!binding.metadata.videoID.length && !IsLikelyVideoThumbnail(image))
            {
                DeArrowInvokeImageSetterWithReplacement(object, command, original, image, nil);
                return;
            }
            if (IsLikelyVideoThumbnail(image))
                binding.originalImage = image;
            DeArrowPreferences *preferences = [DeArrowPreferences sharedPreferences];
            UIImage *replacementImage = preferences.isEnabled && preferences.replaceThumbnails &&
                                                binding.metadata.videoID.length
                                            ? binding.replacementImage
                                            : nil;
            DeArrowInvokeImageSetterWithReplacement(object, command, original, image,
                                                    replacementImage);
            if (replacementImage)
                return;
            if (!IsLikelyVideoThumbnail(image))
                return;
            ApplyThumbnailToObject(object, NO);
        };
    });
}

static BOOL InstallVisibleStateHook(Class targetClass)
{
    SEL selector = NSSelectorFromString(@"didEnterVisibleState");
    if (!HasMethodArguments(targetClass, selector, 2))
        return NO;
    return DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^(id object) {
            DeArrowInvokeVisibleStateWithReplacement(
                object, command, original,
                ^id(id currentObject) {
                    DeArrowPreferences *preferences = [DeArrowPreferences sharedPreferences];
                    if (!preferences.isEnabled || !preferences.replaceThumbnails)
                        return nil;
                    return DeArrowBindingForObject(currentObject, NO).replacementImage;
                },
                ^(id currentObject, id replacementImage) {
                    BrandingBinding *binding = DeArrowBindingForObject(currentObject, NO);
                    if (!binding || binding.replacementImage != replacementImage)
                        return;
                    ApplyReplacementImage(currentObject, binding);
                });
            BrandingBinding *binding = DeArrowBindingForObject(object, NO);
            if (binding.metadata.videoID.length && !binding.replacementImage)
                ApplyThumbnailToObject(object, NO);
        };
    });
}

void DeArrowInstallThumbnailIntegration(void)
{
    for (NSString *className in @[ @"ASImageNode", @"ELMImageNode" ])
    {
        Class imageNodeClass = NSClassFromString(className);
        if (!imageNodeClass)
            continue;
        InstallImageSetter(imageNodeClass);
        InstallVisibleStateHook(imageNodeClass);
    }
}
