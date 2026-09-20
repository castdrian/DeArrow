#import "IntegrationSupport.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "BrandingClient.h"
#import "Preferences.h"
#import "ThumbnailIntegration.h"
#import "TitleIntegration.h"

@implementation BrandingBinding
@end

static void *BrandingBindingKey = &BrandingBindingKey;

static NSHashTable *TitleObjects(void)
{
    static NSHashTable    *objects;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ objects = [NSHashTable weakObjectsHashTable]; });
    return objects;
}

static NSHashTable *ThumbnailObjects(void)
{
    static NSHashTable    *objects;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ objects = [NSHashTable weakObjectsHashTable]; });
    return objects;
}

static void CaptureOriginalVisuals(id object, BrandingBinding *binding)
{
    if (!object || !binding)
        return;
    if (!binding.originalImage && [object respondsToSelector:@selector(image)])
    {
        id image = [object image];
        if ([image isKindOfClass:[UIImage class]])
            binding.originalImage = image;
    }
    if (!binding.originalTitle && [object respondsToSelector:@selector(attributedText)])
        binding.originalTitle = [[object attributedText] copy];
}

BrandingBinding *DeArrowBindingForObject(id object, BOOL create)
{
    if (!object)
        return nil;
    BrandingBinding *binding = objc_getAssociatedObject(object, BrandingBindingKey);
    if (!binding && create)
    {
        binding = [BrandingBinding new];
        objc_setAssociatedObject(object, BrandingBindingKey, binding,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return binding;
}

VideoMetadataRecord *DeArrowStoredMetadataForObject(id object)
{
    return DeArrowBindingForObject(object, NO).metadata;
}

static id DeArrowParentObject(id object)
{
    if (!object)
        return nil;
    static SEL             yogaParentSelector;
    static SEL             supernodeSelector;
    static SEL             superNodeSelector;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        yogaParentSelector = sel_registerName("yogaParent");
        supernodeSelector  = sel_registerName("supernode");
        superNodeSelector  = sel_registerName("superNode");
    });
    SEL selectors[] = {yogaParentSelector, supernodeSelector, superNodeSelector};
    for (NSUInteger index = 0; index < sizeof(selectors) / sizeof(selectors[0]); index++)
    {
        SEL selector = selectors[index];
        if (![object respondsToSelector:selector])
            continue;
        Method method = class_getInstanceMethod(object_getClass(object), selector);
        if (!method)
            continue;
        char returnType[128] = {0};
        method_getReturnType(method, returnType, sizeof(returnType));
        if (returnType[0] != '@')
            continue;
        id parent = ((id (*)(id, SEL)) objc_msgSend)(object, selector);
        if (parent && parent != object)
            return parent;
    }
    return nil;
}

VideoMetadataRecord *DeArrowMetadataForAncestor(id object)
{
    id current = object;
    for (NSUInteger depth = 0; current && depth < 16; depth++)
    {
        current                       = DeArrowParentObject(current);
        VideoMetadataRecord *metadata = DeArrowStoredMetadataForObject(current);
        if (metadata)
            return metadata;
    }
    return nil;
}

void DeArrowAssociateMetadata(id object, VideoMetadataRecord *metadata)
{
    if (!object || !metadata.videoID.length)
        return;
    BrandingBinding *binding = DeArrowBindingForObject(object, YES);
    if ([binding.metadata.videoID isEqualToString:metadata.videoID])
    {
        NSString *title   = metadata.title.length ? metadata.title : binding.metadata.title;
        NSString *channel = metadata.channel.length ? metadata.channel : binding.metadata.channel;
        if (![binding.metadata.title isEqualToString:title] ||
            ![binding.metadata.channel isEqualToString:channel])
            binding.metadata = [[VideoMetadataRecord alloc] initWithVideoID:metadata.videoID
                                                                      title:title
                                                                    channel:channel];
        binding.metadataAttempted = YES;
        if (NSThread.isMainThread)
            CaptureOriginalVisuals(object, binding);
        return;
    }
    [binding.brandingToken cancel];
    [binding.thumbnailBrandingToken cancel];
    [binding.thumbnailToken cancel];
    binding.brandingToken              = nil;
    binding.thumbnailBrandingToken     = nil;
    binding.thumbnailToken             = nil;
    binding.originalTitle              = nil;
    binding.originalImage              = nil;
    binding.brandingResolved           = NO;
    binding.thumbnailBrandingResolved  = NO;
    binding.thumbnailResolved          = NO;
    binding.brandingRetryTime          = 0.0;
    binding.thumbnailBrandingRetryTime = 0.0;
    binding.thumbnailRetryTime         = 0.0;
    binding.generation += 1;
    binding.metadata          = [metadata copy];
    binding.metadataAttempted = YES;
    if (NSThread.isMainThread)
        CaptureOriginalVisuals(object, binding);
}

void DeArrowAssociateVideoID(id object, NSString *videoID)
{
    if (videoID.length == 0)
        return;
    VideoMetadataRecord *existing = DeArrowStoredMetadataForObject(object);
    if (existing && [existing.videoID isEqualToString:videoID])
        return;
    DeArrowAssociateMetadata(object, [[VideoMetadataRecord alloc] initWithVideoID:videoID
                                                                            title:nil
                                                                          channel:nil]);
}

void DeArrowCancelBinding(id object)
{
    BrandingBinding *binding = DeArrowBindingForObject(object, NO);
    [binding.brandingToken cancel];
    [binding.thumbnailBrandingToken cancel];
    [binding.thumbnailToken cancel];
    binding.brandingToken              = nil;
    binding.thumbnailBrandingToken     = nil;
    binding.thumbnailToken             = nil;
    binding.brandingResolved           = NO;
    binding.thumbnailBrandingResolved  = NO;
    binding.thumbnailResolved          = NO;
    binding.brandingRetryTime          = 0.0;
    binding.thumbnailBrandingRetryTime = 0.0;
    binding.thumbnailRetryTime         = 0.0;
    binding.generation += 1;
}

void DeArrowRegisterTitleObject(id object)
{
    if (!object)
        return;
    @synchronized(TitleObjects())
    {
        [TitleObjects() addObject:object];
    }
}

void DeArrowRefreshTitleObjects(void)
{
    void (^refresh)(void) = ^{
        NSArray *objects;
        @synchronized(TitleObjects())
        {
            objects = TitleObjects().allObjects;
        }
        for (id object in objects)
        {
            DeArrowRefreshTitleObject(object);
        }
    };
    if (NSThread.isMainThread)
        refresh();
    else
        dispatch_async(dispatch_get_main_queue(), refresh);
}

void DeArrowRegisterThumbnailObject(id object)
{
    if (!object)
        return;
    @synchronized(ThumbnailObjects())
    {
        [ThumbnailObjects() addObject:object];
    }
}

void DeArrowRefreshThumbnailObjects(void)
{
    void (^refresh)(void) = ^{
        NSArray *objects;
        @synchronized(ThumbnailObjects())
        {
            objects = ThumbnailObjects().allObjects;
        }
        for (id object in objects)
            DeArrowRefreshThumbnailObject(object);
    };
    if (NSThread.isMainThread)
        refresh();
    else
        dispatch_async(dispatch_get_main_queue(), refresh);
}

__attribute__((constructor)) static void DeArrowSupportInitialize(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            addObserverForName:DeArrowPreferencesDidChangeNotification
                        object:nil
                         queue:nil
                    usingBlock:^(__unused NSNotification *notification) {
                        DeArrowRefreshTitleObjects();
                        DeArrowRefreshThumbnailObjects();
                    }];
    });
}
