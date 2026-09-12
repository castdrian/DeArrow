#import "ThumbnailIntegration.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "BrandingClient.h"
#import "HookSupport.h"
#import "IntegrationSupport.h"
#import "Metadata.h"
#import "Preferences.h"

static void ApplyThumbnailToObject(id object, BOOL animated) {
    if (!object || [DeArrowPreferences sharedPreferences].isEnabled == NO ||
        [DeArrowPreferences sharedPreferences].replaceThumbnails == NO)
        return;
    BrandingBinding *binding = DeArrowBindingForObject(object, YES);
    DeArrowRegisterThumbnailObject(object);
    VideoMetadataRecord *metadata = DeArrowStoredMetadataForObject(object);
    if (!metadata)
        metadata = DeArrowMetadataFromParents(object);
    if (!metadata || !metadata.videoID.length)
        return;
    if (!binding.metadata || ![binding.metadata.videoID isEqualToString:metadata.videoID])
        DeArrowAssociateMetadata(object, metadata);
    binding = DeArrowBindingForObject(object, YES);
    if (binding.thumbnailBrandingToken || binding.thumbnailBrandingResolved ||
        binding.thumbnailBrandingRetryTime > [NSDate date].timeIntervalSince1970)
        return;
    NSString *videoID = metadata.videoID;
    NSUInteger generation = binding.generation;
    __weak id weakObject = object;
    __weak BrandingBinding *weakBinding = binding;
    binding.thumbnailBrandingToken = [[BrandingClient sharedClient] requestBrandingForVideoID:videoID
                                                                                     completion:^(BrandingRecord *record, NSError *error) {
        id strongObject = weakObject;
        BrandingBinding *strongBinding = weakBinding;
        if (!strongObject || !strongBinding || strongBinding.generation != generation ||
            ![strongBinding.metadata.videoID isEqualToString:videoID])
            return;
        strongBinding.thumbnailBrandingToken = nil;
        strongBinding.thumbnailBrandingResolved = error == nil;
        strongBinding.thumbnailBrandingRetryTime = error ? [NSDate date].timeIntervalSince1970 + 10.0 : 0.0;
        if (!record.thumbnailURL)
            return;
        if (![DeArrowPreferences sharedPreferences].isEnabled ||
            ![DeArrowPreferences sharedPreferences].replaceThumbnails)
            return;
        if (strongBinding.thumbnailToken || strongBinding.thumbnailResolved ||
            strongBinding.thumbnailRetryTime > [NSDate date].timeIntervalSince1970)
            return;
        strongBinding.thumbnailToken = [[BrandingClient sharedClient] requestThumbnailForVideoID:videoID
                                                                                        completion:^(UIImage *image, NSError *thumbnailError) {
            id currentObject = weakObject;
            BrandingBinding *currentBinding = weakBinding;
            if (!currentObject || !currentBinding || currentBinding.generation != generation ||
                ![currentBinding.metadata.videoID isEqualToString:videoID])
                return;
            currentBinding.thumbnailToken = nil;
            currentBinding.thumbnailResolved = image != nil && thumbnailError == nil;
            currentBinding.thumbnailRetryTime = currentBinding.thumbnailResolved ? 0.0 : [NSDate date].timeIntervalSince1970 + 10.0;
            if (!image)
                return;
            if (currentBinding.applyingThumbnail)
                return;
            currentBinding.applyingThumbnail = YES;
            if ([currentObject respondsToSelector:@selector(setImage:animated:)])
                ((void (*)(id, SEL, UIImage *, BOOL))objc_msgSend)(currentObject, @selector(setImage:animated:), image, NO);
            else if ([currentObject respondsToSelector:@selector(setImage:)])
                [currentObject setImage:image];
            currentBinding.applyingThumbnail = NO;
        }];
    }];
    if (animated)
        [object setNeedsLayout];
}

void DeArrowRefreshThumbnailObject(id object) {
    if (!object)
        return;
    BrandingBinding *binding = DeArrowBindingForObject(object, NO);
    if (!binding)
        return;
    DeArrowPreferences *preferences = [DeArrowPreferences sharedPreferences];
    if (!preferences.isEnabled || !preferences.replaceThumbnails) {
        [binding.thumbnailBrandingToken cancel];
        [binding.thumbnailToken cancel];
        binding.thumbnailBrandingToken = nil;
        binding.thumbnailToken = nil;
        binding.thumbnailBrandingResolved = NO;
        binding.thumbnailResolved = NO;
        binding.thumbnailBrandingRetryTime = 0.0;
        binding.thumbnailRetryTime = 0.0;
        if (binding.originalImage && !binding.applyingThumbnail) {
            binding.applyingThumbnail = YES;
            if ([object respondsToSelector:@selector(setImage:animated:)])
                ((void (*)(id, SEL, UIImage *, BOOL))objc_msgSend)(object, @selector(setImage:animated:), binding.originalImage, NO);
            else if ([object respondsToSelector:@selector(setImage:)])
                [object setImage:binding.originalImage];
            binding.applyingThumbnail = NO;
        }
        return;
    }
    ApplyThumbnailToObject(object, NO);
}

static void BindRelatedLabels(UIView *imageView, NSString *videoID) {
    if (!imageView || !videoID.length)
        return;
    BrandingBinding *binding = DeArrowBindingForObject(imageView, YES);
    if (binding.relatedViewsBound)
        return;
    UIView *current = imageView;
    for (NSUInteger depth = 0; depth < 4; depth++) {
        UIView *parent = current.superview;
        if (!parent)
            break;
        for (UIView *candidate in parent.subviews) {
            if (candidate == imageView)
                continue;
            NSString *identifier = candidate.accessibilityIdentifier.lowercaseString;
            NSString *className = NSStringFromClass([candidate class]).lowercaseString;
            if ([className containsString:@"formattedstringlabel"] ||
                [identifier containsString:@"title"] || [identifier containsString:@"headline"]) {
                DeArrowAssociateVideoID(candidate, videoID);
            }
        }
        current = parent;
    }
    binding.relatedViewsBound = YES;
}

static void InstallImageNodeSetter(Class targetClass) {
    SEL selector = @selector(setImage:);
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^(id object, SEL selector, UIImage *image) {
            BrandingBinding *binding = DeArrowBindingForObject(object, NO);
            ((void (*)(id, SEL, UIImage *))original)(object, selector, image);
            if (!binding || !binding.applyingThumbnail) {
                binding = DeArrowBindingForObject(object, YES);
                binding.originalImage = image;
            }
            if (!binding.applyingThumbnail)
                ApplyThumbnailToObject(object, NO);
        };
    });
}

static void InstallImageLoadCallback(Class targetClass) {
    SEL selector = @selector(imageNode:didLoadImage:);
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^(id object, SEL selector, id node, UIImage *image) {
            ((void (*)(id, SEL, id, UIImage *))original)(object, selector, node, image);
            BrandingBinding *binding = DeArrowBindingForObject(node, YES);
            binding.originalImage = image;
            BrandingBinding *objectBinding = DeArrowBindingForObject(object, YES);
            objectBinding.originalImage = image;
            ApplyThumbnailToObject(object, NO);
        };
    });
}

static void InstallThumbnailControllerInitializer(Class targetClass) {
    SEL selector = NSSelectorFromString(@"initWithImageView:URLs:imageService:");
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^id(id object, SEL selector, UIView *imageView, NSDictionary *URLs, id imageService) {
            id result = ((id (*)(id, SEL, UIView *, NSDictionary *, id))original)(object, selector, imageView, URLs, imageService);
            NSString *videoID;
            for (id value in URLs.allValues) {
                videoID = [VideoMetadataAdapters videoIDFromURL:value];
                if (videoID.length)
                    break;
            }
            if (videoID.length) {
                DeArrowAssociateVideoID(result, videoID);
                DeArrowAssociateVideoID(imageView, videoID);
                BindRelatedLabels(imageView, videoID);
            }
            return result;
        };
    });
}

static void InstallImageViewSetter(Class targetClass) {
    SEL selector = @selector(setImage:animated:);
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^(id object, SEL selector, UIImage *image, BOOL animated) {
            ((void (*)(id, SEL, UIImage *, BOOL))original)(object, selector, image, animated);
            BrandingBinding *binding = DeArrowBindingForObject(object, NO);
            if (!binding || !binding.applyingThumbnail) {
                binding = DeArrowBindingForObject(object, YES);
                binding.originalImage = image;
            }
            if (!binding.applyingThumbnail) {
                VideoMetadataRecord *metadata = DeArrowStoredMetadataForObject(object);
                if (!metadata) {
                    id delegate = [object respondsToSelector:@selector(delegate)] ? [object delegate] : nil;
                    metadata = DeArrowStoredMetadataForObject(delegate);
                    if (metadata)
                        DeArrowAssociateMetadata(object, metadata);
                }
                if (metadata)
                    BindRelatedLabels((UIView *)object, metadata.videoID);
                ApplyThumbnailToObject(object, animated);
            }
        };
    });
}

static void InstallReuseCancellation(Class targetClass) {
    SEL selector = @selector(prepareForReuse);
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^(id object, SEL selector) {
            ((void (*)(id, SEL))original)(object, selector);
            DeArrowCancelBinding(object);
        };
    });
}

static void InstallWindowCancellation(Class targetClass) {
    SEL selector = @selector(didMoveToWindow);
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^(id object, SEL selector) {
            ((void (*)(id, SEL))original)(object, selector);
            if (![object window])
                DeArrowCancelBinding(object);
        };
    });
}

void DeArrowInstallThumbnailIntegration(void) {
    for (NSString *className in @[@"ELMImageNode", @"ASNetworkImageNode", @"ASImageNode"]) {
        Class imageNodeClass = NSClassFromString(className);
        if (imageNodeClass) {
            InstallImageNodeSetter(imageNodeClass);
            InstallImageLoadCallback(imageNodeClass);
        }
    }
    Class thumbnailControllerClass = NSClassFromString(@"YTThumbnailController");
    if (thumbnailControllerClass)
        InstallThumbnailControllerInitializer(thumbnailControllerClass);
    Class imageViewClass = NSClassFromString(@"YTImageView");
    if (imageViewClass) {
        InstallImageViewSetter(imageViewClass);
        InstallWindowCancellation(imageViewClass);
    }
    InstallReuseCancellation([UICollectionViewCell class]);
    for (NSString *className in @[@"ELMCellNode", @"YTVideoNode", @"YTVideoWithContextNode", @"YTShortsNode", @"YTReelNode"])
        InstallReuseCancellation(NSClassFromString(className));
    static dispatch_once_t notificationToken;
    dispatch_once(&notificationToken, ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:DeArrowPreferencesDidChangeNotification
                                                            object:nil
                                                             queue:[NSOperationQueue mainQueue]
                                                        usingBlock:^(__unused NSNotification *notification) {
            DeArrowRefreshThumbnailObjects();
        }];
    });
}
