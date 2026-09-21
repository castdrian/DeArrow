#import "NodeIntegration.h"

#import <objc/runtime.h>
#import <string.h>
#import <substrate.h>

#import "HookSupport.h"
#import "IntegrationSupport.h"
#import "Metadata.h"

static void *NodeElementKey = &NodeElementKey;
static IMP   OriginalElementImplementation;

static BOOL DeclaresMethod(Class targetClass, SEL selector)
{
    if (!targetClass)
        return NO;
    unsigned int count = 0;
    Method      *list  = class_copyMethodList(targetClass, &count);
    BOOL         found = NO;
    for (unsigned int index = 0; index < count; index++)
    {
        if (method_getName(list[index]) == selector)
        {
            found = YES;
            break;
        }
    }
    free(list);
    return found;
}

static BOOL IsVideoNode(id object)
{
    if (!object)
        return NO;
    for (Class current = object_getClass(object); current; current = class_getSuperclass(current))
    {
        const char *name = class_getName(current);
        if (!name)
            continue;
        if (strcmp(name, "YTVideoNode") == 0 || strcmp(name, "YTVideoWithContextNode") == 0 ||
            strcmp(name, "YTGridVideoNode") == 0 || strcmp(name, "YTShortsNode") == 0 ||
            strcmp(name, "YTShortsVideoNode") == 0 || strcmp(name, "YTReelNode") == 0 ||
            strcmp(name, "YTReelItemNode") == 0 || strstr(name, "Video") ||
            strstr(name, "Shorts") || strstr(name, "Reel"))
            return YES;
    }
    return NO;
}

static void AssociateElementMetadata(id object, id element)
{
    if (!object || !element || !IsVideoNode(object))
        return;
    id previousElement = objc_getAssociatedObject(object, NodeElementKey);
    if (previousElement == element)
    {
        BrandingBinding *binding = DeArrowBindingForObject(object, NO);
        if (binding && (binding.metadata || binding.metadataAttempted))
            return;
    }
    else
    {
        objc_setAssociatedObject(object, NodeElementKey, element,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [VideoMetadataAdapters invalidateNode:object];
        DeArrowResetBindingForReuse(object);
    }
    VideoMetadataRecord *metadata = [VideoMetadataAdapters recordForNode:object];
    if (!metadata)
    {
        DeArrowBindingForObject(object, YES).metadataAttempted = YES;
        return;
    }
    DeArrowAssociateMetadata(object, metadata);
}

static void HookedElementSetter(id object, SEL selector, id element)
{
    ((void (*)(id, SEL, id)) OriginalElementImplementation)(object, selector, element);
    AssociateElementMetadata(object, element);
}

static void InstallElementHook(Class targetClass)
{
    SEL    selector = @selector(setElement:);
    Method method   = targetClass ? class_getInstanceMethod(targetClass, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 3)
        return;
    char argumentType[128] = {0};
    method_getArgumentType(method, 2, argumentType, sizeof(argumentType));
    if (argumentType[0] != '@')
        return;
    MSHookMessageEx(targetClass, selector, (IMP) HookedElementSetter,
                    &OriginalElementImplementation);
}

static void InstallNodeLoadHook(Class targetClass, BOOL allowInherited)
{
    SEL selector = @selector(didLoad);
    if (!allowInherited && !DeclaresMethod(targetClass, selector))
        return;
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^(id object, SEL selector) {
            ((void (*)(id, SEL)) original)(object, selector);
            if (!IsVideoNode(object))
                return;
            if (DeArrowStoredMetadataForObject(object))
                return;
            VideoMetadataRecord *metadata = [VideoMetadataAdapters recordForNode:object];
            if (!metadata)
            {
                DeArrowBindingForObject(object, YES).metadataAttempted = YES;
                return;
            }
            DeArrowAssociateMetadata(object, metadata);
        };
    });
}

void DeArrowInstallNodeIntegration(void)
{
    Class baseClass = NSClassFromString(@"ELMCellNode");
    if (baseClass && !OriginalElementImplementation)
        InstallElementHook(baseClass);

    for (NSString *className in @[
             @"YTVideoNode", @"YTVideoWithContextNode", @"YTGridVideoNode", @"YTShortsNode",
             @"YTShortsVideoNode", @"YTReelNode"
         ])
    {
        Class cellNodeClass = NSClassFromString(className);
        if (!cellNodeClass)
            continue;
        InstallNodeLoadHook(cellNodeClass, NO);
    }
}
