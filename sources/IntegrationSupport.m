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

static NSMutableDictionary<NSString *, VideoMetadataRecord *> *MetadataByTitle(void)
{
    static NSMutableDictionary *metadata;
    static dispatch_once_t      onceToken;
    dispatch_once(&onceToken, ^{ metadata = [NSMutableDictionary dictionary]; });
    return metadata;
}

static NSMutableSet<NSString *> *AmbiguousMetadataTitles(void)
{
    static NSMutableSet   *titles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ titles = [NSMutableSet set]; });
    return titles;
}

static NSString *MetadataTitleKey(NSString *title)
{
    NSString *trimmed =
        [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length > 0 ? trimmed.lowercaseString : nil;
}

static void IndexMetadataTitle(VideoMetadataRecord *metadata)
{
    NSString *key = MetadataTitleKey(metadata.title);
    if (!key.length)
        return;
    BOOL shouldResolve = NO;
    @synchronized(MetadataByTitle())
    {
        if ([AmbiguousMetadataTitles() containsObject:key])
            return;
        VideoMetadataRecord *existing = MetadataByTitle()[key];
        if (!existing)
        {
            if (MetadataByTitle().count >= 1024)
                [MetadataByTitle() removeObjectForKey:MetadataByTitle().allKeys.firstObject];
            MetadataByTitle()[key] = metadata;
            shouldResolve          = YES;
        }
        else if (![existing.videoID isEqualToString:metadata.videoID])
        {
            [MetadataByTitle() removeObjectForKey:key];
            [AmbiguousMetadataTitles() addObject:key];
        }
        else
            shouldResolve = YES;
    }
    if (shouldResolve)
        DeArrowResolveTitleObjectsForMetadata(metadata);
}

VideoMetadataRecord *DeArrowMetadataForTitleText(NSString *text)
{
    NSString *key = MetadataTitleKey(text);
    if (!key.length)
        return nil;
    @synchronized(MetadataByTitle())
    {
        if ([AmbiguousMetadataTitles() containsObject:key])
            return nil;
        return MetadataByTitle()[key];
    }
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

VideoMetadataRecord *DeArrowMetadataForNodeAncestor(id object)
{
    static SEL             supernodeSelector;
    static SEL             superNodeSelector;
    static SEL             yogaParentSelector;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        supernodeSelector  = sel_registerName("supernode");
        superNodeSelector  = sel_registerName("superNode");
        yogaParentSelector = sel_registerName("yogaParent");
    });
    id current = object;
    for (NSUInteger depth = 0; current && depth < 8; depth++)
    {
        VideoMetadataRecord *metadata = DeArrowStoredMetadataForObject(current);
        if (metadata)
            return metadata;
        id  parent      = nil;
        SEL selectors[] = {supernodeSelector, yogaParentSelector, superNodeSelector};
        for (NSUInteger index = 0; index < sizeof(selectors) / sizeof(selectors[0]); index++)
        {
            SEL selector = selectors[index];
            if (![current respondsToSelector:selector])
                continue;
            @try
            {
                parent = ((id (*)(id, SEL)) objc_msgSend)(current, selector);
            }
            @catch (__unused NSException *exception)
            {
                parent = nil;
            }
            if (parent && parent != current)
                break;
        }
        if (!parent || parent == current)
            break;
        current = parent;
    }
    return nil;
}

VideoMetadataRecord *DeArrowMetadataForUIKitAncestor(id object)
{
    static SEL             superviewSelector;
    static SEL             nextResponderSelector;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        superviewSelector     = @selector(superview);
        nextResponderSelector = @selector(nextResponder);
    });
    id current = object;
    for (NSUInteger depth = 0; current && depth < 8; depth++)
    {
        VideoMetadataRecord *metadata = DeArrowStoredMetadataForObject(current);
        if (metadata)
            return metadata;
        id  parent      = nil;
        SEL selectors[] = {superviewSelector, nextResponderSelector};
        for (NSUInteger index = 0; index < sizeof(selectors) / sizeof(selectors[0]); index++)
        {
            SEL selector = selectors[index];
            if (![current respondsToSelector:selector])
                continue;
            @try
            {
                parent = ((id (*)(id, SEL)) objc_msgSend)(current, selector);
            }
            @catch (__unused NSException *exception)
            {
                parent = nil;
            }
            if (parent && parent != current)
                break;
            parent = nil;
        }
        if (!parent || parent == current)
            break;
        current = parent;
    }
    return nil;
}

void DeArrowAssociateMetadata(id object, VideoMetadataRecord *metadata)
{
    if (!object || !metadata.videoID.length)
        return;
    IndexMetadataTitle(metadata);
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
    binding.replacementImage           = nil;
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
    binding.replacementImage           = nil;
    binding.brandingRetryTime          = 0.0;
    binding.thumbnailBrandingRetryTime = 0.0;
    binding.thumbnailRetryTime         = 0.0;
    binding.generation += 1;
}

void DeArrowResetBindingForReuse(id object)
{
    BrandingBinding *binding = DeArrowBindingForObject(object, NO);
    if (!binding)
        return;
    [binding.brandingToken cancel];
    [binding.thumbnailBrandingToken cancel];
    [binding.thumbnailToken cancel];
    BrandingBinding *replacement  = [BrandingBinding new];
    replacement.generation        = binding.generation + 1;
    replacement.metadataAttempted = NO;
    objc_setAssociatedObject(object, BrandingBindingKey, replacement,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
