#import "IntegrationSupport.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "BrandingClient.h"
#import "Preferences.h"
#import "TitleIntegration.h"

@implementation BrandingBinding
@end

@interface NSObject (DeArrowViewControllerLookup)
- (UIViewController *)_viewControllerForAncestor;
@end

static void *BrandingBindingKey = &BrandingBindingKey;

static NSHashTable *TitleObjects(void) {
    static NSHashTable *objects;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        objects = [NSHashTable weakObjectsHashTable];
    });
    return objects;
}

BrandingBinding *DeArrowBindingForObject(id object, BOOL create) {
    if (!object)
        return nil;
    BrandingBinding *binding = objc_getAssociatedObject(object, BrandingBindingKey);
    if (!binding && create) {
        binding = [BrandingBinding new];
        objc_setAssociatedObject(object, BrandingBindingKey, binding, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return binding;
}

VideoMetadataRecord *DeArrowStoredMetadataForObject(id object) {
    return DeArrowBindingForObject(object, NO).metadata;
}

void DeArrowAssociateMetadata(id object, VideoMetadataRecord *metadata) {
    if (!object || !metadata.videoID.length)
        return;
    BrandingBinding *binding = DeArrowBindingForObject(object, YES);
    if ([binding.metadata.videoID isEqualToString:metadata.videoID] &&
        (!metadata.title.length || [binding.metadata.title isEqualToString:metadata.title])) {
        if (!binding.metadata.title.length && metadata.title.length)
            binding.metadata = metadata;
        return;
    }
    [binding.brandingToken cancel];
    [binding.thumbnailBrandingToken cancel];
    [binding.thumbnailToken cancel];
    binding.brandingToken = nil;
    binding.thumbnailBrandingToken = nil;
    binding.thumbnailToken = nil;
    binding.originalTitle = nil;
    binding.relatedViewsBound = NO;
    binding.generation += 1;
    binding.metadata = [metadata copy];
    binding.metadataAttempted = YES;
}

void DeArrowAssociateVideoID(id object, NSString *videoID) {
    if (videoID.length == 0)
        return;
    VideoMetadataRecord *existing = DeArrowStoredMetadataForObject(object);
    if (existing && [existing.videoID isEqualToString:videoID])
        return;
    DeArrowAssociateMetadata(object, [[VideoMetadataRecord alloc] initWithVideoID:videoID title:nil channel:nil]);
}

void DeArrowPropagateMetadata(id parent, id child) {
    VideoMetadataRecord *metadata = DeArrowStoredMetadataForObject(parent);
    if (metadata)
        DeArrowAssociateMetadata(child, metadata);
}

static id ExplicitValue(id object, NSString *key) {
    if (!object || key.length == 0)
        return nil;
    SEL selector = NSSelectorFromString(key);
    if (![object respondsToSelector:selector])
        return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

VideoMetadataRecord *DeArrowMetadataForObject(id object) {
    if (!object)
        return nil;
    BrandingBinding *binding = DeArrowBindingForObject(object, YES);
    if (binding.metadata)
        return binding.metadata;
    if (binding.metadataAttempted)
        return nil;
    binding.metadataAttempted = YES;
    VideoMetadataRecord *metadata = [VideoMetadataAdapters recordForNode:object];
    if (metadata)
        DeArrowAssociateMetadata(object, metadata);
    return metadata;
}

VideoMetadataRecord *DeArrowMetadataFromParents(id object) {
    if (!object)
        return nil;
    VideoMetadataRecord *metadata = DeArrowStoredMetadataForObject(object);
    if (metadata)
        return metadata;
    id current = object;
    NSString *className = NSStringFromClass([object class]);
    BOOL nodeObject = [className containsString:@"Node"];
    for (NSUInteger depth = 0; depth < 12; depth++) {
        id parent;
        if (nodeObject && [current respondsToSelector:@selector(yogaParent)])
            parent = ExplicitValue(current, @"yogaParent");
        else if ([current respondsToSelector:@selector(superview)])
            parent = [current superview];
        if (!parent)
            break;
        metadata = DeArrowStoredMetadataForObject(parent);
        if (metadata)
            return metadata;
        current = parent;
    }
    if ([object respondsToSelector:@selector(_viewControllerForAncestor)]) {
        UIViewController *viewController = [object _viewControllerForAncestor];
        metadata = DeArrowStoredMetadataForObject(viewController);
        if (metadata)
            return metadata;
        metadata = DeArrowMetadataForObject(viewController);
    }
    return metadata;
}

void DeArrowCancelBinding(id object) {
    BrandingBinding *binding = DeArrowBindingForObject(object, NO);
    [binding.brandingToken cancel];
    [binding.thumbnailBrandingToken cancel];
    [binding.thumbnailToken cancel];
    binding.brandingToken = nil;
    binding.thumbnailBrandingToken = nil;
    binding.thumbnailToken = nil;
    binding.generation += 1;
    binding.relatedViewsBound = NO;
}

void DeArrowRegisterTitleObject(id object) {
    if (!object)
        return;
    @synchronized (TitleObjects()) {
        [TitleObjects() addObject:object];
    }
}

void DeArrowRefreshTitleObjects(void) {
    void (^refresh)(void) = ^{
        NSArray *objects;
        @synchronized (TitleObjects()) {
            objects = TitleObjects().allObjects;
        }
        for (id object in objects) {
            DeArrowRefreshTitleObject(object);
        }
    };
    if (NSThread.isMainThread)
        refresh();
    else
        dispatch_async(dispatch_get_main_queue(), refresh);
}

__attribute__((constructor)) static void DeArrowSupportInitialize(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:DeArrowPreferencesDidChangeNotification
                                                            object:nil
                                                             queue:nil
                                                        usingBlock:^(__unused NSNotification *notification) {
            DeArrowRefreshTitleObjects();
        }];
    });
}
