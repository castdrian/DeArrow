#import "NodeIntegration.h"

#import "HookSupport.h"
#import "IntegrationSupport.h"
#import "Metadata.h"

static void ResetNodeBinding(id object)
{
    if (!object)
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
}

static void InstallElementHook(Class targetClass)
{
    SEL selector = @selector(setElement:);
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^(id object, SEL selector, id element) {
            ((void (*)(id, SEL, id)) original)(object, selector, element);
            ResetNodeBinding(object);
            VideoMetadataRecord *metadata = [VideoMetadataAdapters recordForNode:object];
            if (metadata)
                DeArrowAssociateMetadata(object, metadata);
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
                    DeArrowAssociateMetadata(object, metadata);
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
