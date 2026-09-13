#import "NodeIntegration.h"

#import <objc/runtime.h>

#import "HookSupport.h"
#import "IntegrationSupport.h"
#import "Metadata.h"
#import "TitleIntegration.h"

static NSArray *NodeChildren(id object)
{
    if (!object || ![object respondsToSelector:NSSelectorFromString(@"yogaChildren")])
        return nil;
    @try
    {
        id children = [object valueForKey:@"yogaChildren"];
        return [children isKindOfClass:[NSArray class]] ? children : nil;
    }
    @catch (__unused NSException *exception)
    {
        return nil;
    }
}

static BOOL NodeHasKnownClass(id object, NSArray<NSString *> *classNames)
{
    if (!object)
        return NO;
    for (Class current = object_getClass(object); current; current = class_getSuperclass(current))
    {
        if ([classNames containsObject:NSStringFromClass(current)])
            return YES;
    }
    return NO;
}

static BOOL IsTitleMetadataTarget(id object)
{
    return NodeHasKnownClass(object, @[ @"ASTextNode", @"ELMTextNode", @"YTFormattedStringLabel" ]);
}

static BOOL IsThumbnailMetadataTarget(id object)
{
    return NodeHasKnownClass(object, @[ @"ASImageNode", @"ELMImageNode", @"ASNetworkImageNode" ]);
}

static void ResetNodeBinding(id object, NSUInteger depth)
{
    if (!object || depth > 12)
        return;
    BrandingBinding *binding = DeArrowBindingForObject(object, NO);
    if (binding)
    {
        DeArrowCancelBinding(object);
        binding.metadata          = nil;
        binding.metadataAttempted = NO;
        binding.originalTitle     = nil;
        binding.originalImage     = nil;
    }
    for (id child in NodeChildren(object))
        ResetNodeBinding(child, depth + 1);
}

static void AssociateNodeMetadata(id object, VideoMetadataRecord *metadata, NSUInteger depth)
{
    if (!object || !metadata || depth > 12)
        return;
    if (depth == 0 || IsTitleMetadataTarget(object) || IsThumbnailMetadataTarget(object))
    {
        DeArrowAssociateMetadata(object, metadata);
        if (IsThumbnailMetadataTarget(object))
            DeArrowRegisterThumbnailObject(object);
    }
    for (id child in NodeChildren(object))
        AssociateNodeMetadata(child, metadata, depth + 1);
}

void DeArrowAssociateMetadataTree(id object, VideoMetadataRecord *metadata)
{
    AssociateNodeMetadata(object, metadata, 0);
}

static void InstallElementHook(Class targetClass)
{
    SEL selector = @selector(setElement:);
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^(id object, SEL selector, id element) {
            ((void (*)(id, SEL, id)) original)(object, selector, element);
            ResetNodeBinding(object, 0);
            VideoMetadataRecord *metadata = [VideoMetadataAdapters recordForNode:object];
            if (metadata)
            {
                AssociateNodeMetadata(object, metadata, 0);
                DeArrowRefreshTitleTree(object);
            }
            else
                DeArrowBindingForObject(object, YES).metadataAttempted = YES;
        };
    });
}

static void InstallNodeLoadHook(Class targetClass)
{
    SEL selector = @selector(didLoad);
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^(id object, SEL selector) {
            ((void (*)(id, SEL)) original)(object, selector);
            if (!DeArrowStoredMetadataForObject(object))
            {
                VideoMetadataRecord *metadata = [VideoMetadataAdapters recordForNode:object];
                if (metadata)
                {
                    DeArrowAssociateMetadata(object, metadata);
                    DeArrowRefreshTitleTree(object);
                }
            }
        };
    });
}

void DeArrowInstallNodeIntegration(void)
{
    for (NSString *className in @[
             @"ELMCellNode", @"YTVideoNode", @"YTVideoWithContextNode", @"YTGridVideoNode",
             @"YTShortsNode", @"YTShortsVideoNode", @"YTReelNode"
         ])
    {
        Class cellNodeClass = NSClassFromString(className);
        if (cellNodeClass)
        {
            InstallElementHook(cellNodeClass);
            InstallNodeLoadHook(cellNodeClass);
        }
    }
}
