#import "NodeIntegration.h"

#import <objc/runtime.h>
#import <string.h>
#import <substrate.h>

#import "HookSupport.h"
#import "IntegrationSupport.h"
#import "Metadata.h"
#import "ThumbnailIntegration.h"
#import "TitleIntegration.h"

static void *NodeElementKey = &NodeElementKey;
static id    NodeValue(id object, NSString *key);

static BOOL IsTextNode(id object)
{
    if (!object)
        return NO;
    for (Class current = object_getClass(object); current; current = class_getSuperclass(current))
        if ([NSStringFromClass(current) isEqualToString:@"ELMTextNode"])
            return YES;
    return NO;
}

static BOOL IsImageNode(id object)
{
    if (!object)
        return NO;
    for (Class current = object_getClass(object); current; current = class_getSuperclass(current))
    {
        NSString *name = NSStringFromClass(current);
        if ([name isEqualToString:@"ELMImageNode"] || [name isEqualToString:@"ASImageNode"] ||
            [name isEqualToString:@"ASNetworkImageNode"])
            return YES;
    }
    return NO;
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

static BOOL IsElementsNode(id object)
{
    if (!object)
        return NO;
    NSSet *classes = [NSSet setWithObject:@"ELMCellNode"];
    for (Class current = object_getClass(object); current; current = class_getSuperclass(current))
        if ([classes containsObject:NSStringFromClass(current)])
            return YES;
    return NO;
}

static BOOL IsMetadataNode(id object)
{
    return IsVideoNode(object) || IsElementsNode(object);
}

static BOOL IsElementOwnerNode(id object)
{
    return IsVideoNode(object) || IsElementsNode(object);
}

static VideoMetadataRecord *MergedMetadata(VideoMetadataRecord *base,
                                           VideoMetadataRecord *candidate)
{
    if (!base.videoID.length)
        return candidate;
    if (!candidate.videoID.length || ![base.videoID isEqualToString:candidate.videoID])
        return base;
    NSString *title   = base.title.length ? base.title : candidate.title;
    NSString *channel = base.channel.length ? base.channel : candidate.channel;
    if ([title isEqualToString:base.title] && [channel isEqualToString:base.channel])
        return base;
    return [[VideoMetadataRecord alloc] initWithVideoID:base.videoID title:title channel:channel];
}

static id NodeValue(id object, NSString *key)
{
    if (!object || key.length == 0)
        return nil;
    SEL selector = NSSelectorFromString(key);
    if (![object respondsToSelector:selector])
        return nil;
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!method || method_getNumberOfArguments(method) != 2)
        return nil;
    char returnType[128] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    if (returnType[0] != '@')
        return nil;
    @try
    {
        id value = ((id (*)(id, SEL)) objc_msgSend)(object, selector);
        if (value)
            return value;
    }
    @catch (__unused NSException *exception)
    {
    }
    Ivar ivar = class_getInstanceVariable(object_getClass(object),
                                          [NSString stringWithFormat:@"_%@", key].UTF8String);
    if (!ivar)
        ivar = class_getInstanceVariable(object_getClass(object), key.UTF8String);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return type && type[0] == '@' ? object_getIvar(object, ivar) : nil;
}

static id VideoAncestor(id object)
{
    id current = object;
    for (NSUInteger depth = 0; current && depth < 8; depth++)
    {
        if (IsVideoNode(current))
            return current;
        id parent = NodeValue(current, @"supernode");
        if (!parent || parent == current)
            parent = NodeValue(current, @"superNode");
        if (!parent || parent == current)
            break;
        current = parent;
    }
    return nil;
}

static void BindMetadata(id object, id element, VideoMetadataRecord *metadata);

static NSMapTable *PendingVisualNodesByOwner(void)
{
    static NSMapTable     *nodes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ nodes = [NSMapTable weakToStrongObjectsMapTable]; });
    return nodes;
}

static void RememberPendingVisualNode(id node)
{
    id owner = VideoAncestor(node);
    if (!owner || !node)
        return;
    @synchronized(PendingVisualNodesByOwner())
    {
        NSHashTable *nodes = [PendingVisualNodesByOwner() objectForKey:owner];
        if (!nodes)
        {
            if (PendingVisualNodesByOwner().count >= 256)
                [PendingVisualNodesByOwner()
                    removeObjectForKey:PendingVisualNodesByOwner().keyEnumerator.nextObject];
            nodes = [NSHashTable weakObjectsHashTable];
            [PendingVisualNodesByOwner() setObject:nodes forKey:owner];
        }
        if (nodes.count < 32)
            [nodes addObject:node];
    }
}

static void ResolvePendingVisualNodes(id owner, VideoMetadataRecord *metadata)
{
    if (!owner || !metadata.videoID.length)
        return;
    NSArray *nodes;
    @synchronized(PendingVisualNodesByOwner())
    {
        nodes = [[PendingVisualNodesByOwner() objectForKey:owner] allObjects];
        [PendingVisualNodesByOwner() removeObjectForKey:owner];
    }
    for (id node in nodes)
    {
        if (VideoAncestor(node) != owner)
            continue;
        BindMetadata(node, objc_getAssociatedObject(node, NodeElementKey), metadata);
    }
}

static NSMapTable *PendingElementNodes(void)
{
    static NSMapTable     *nodes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ nodes = [NSMapTable strongToWeakObjectsMapTable]; });
    return nodes;
}

static void RememberPendingElementNode(id element, id node)
{
    if (!element || !node)
        return;
    @synchronized(PendingElementNodes())
    {
        NSHashTable *nodes = [PendingElementNodes() objectForKey:element];
        if (!nodes)
        {
            if (PendingElementNodes().count >= 256)
                [PendingElementNodes()
                    removeObjectForKey:PendingElementNodes().keyEnumerator.nextObject];
            nodes = [NSHashTable weakObjectsHashTable];
            [PendingElementNodes() setObject:nodes forKey:element];
        }
        if (nodes.count < 32)
            [nodes addObject:node];
    }
}

static void ResolvePendingElementNodes(id element, VideoMetadataRecord *metadata)
{
    if (!element || !metadata.videoID.length)
        return;
    NSArray *nodes;
    @synchronized(PendingElementNodes())
    {
        NSHashTable *pending = [PendingElementNodes() objectForKey:element];
        nodes                = [pending.allObjects copy];
        [PendingElementNodes() removeObjectForKey:element];
    }
    for (id node in nodes)
    {
        if (!node)
            continue;
        objc_setAssociatedObject(node, NodeElementKey, element, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DeArrowAssociateMetadata(node, metadata);
        if (IsTextNode(node))
            DeArrowCaptureTitleObject(node, metadata);
        else if (IsImageNode(node))
            DeArrowRefreshThumbnailObject(node);
    }
}

static void BindMetadata(id object, id element, VideoMetadataRecord *metadata)
{
    if (!object || !metadata.videoID.length)
        return;
    if (element)
    {
        objc_setAssociatedObject(object, NodeElementKey, element,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DeArrowAssociateMetadata(element, metadata);
        ResolvePendingElementNodes(element, metadata);
    }
    DeArrowAssociateMetadata(object, metadata);
    if (IsTextNode(object))
        DeArrowCaptureTitleObject(object, metadata);
    else if (IsImageNode(object))
        DeArrowRefreshThumbnailObject(object);
    if (IsVideoNode(object))
        ResolvePendingVisualNodes(object, metadata);
}

static void RequestElementMetadata(id object, id element)
{
    if (!element || !IsElementOwnerNode(object))
        return;
    DeArrowBindingForObject(object, YES).metadataAttempted = YES;
    __weak id weakObject                                   = object;
    __weak id weakElement                                  = element;
    [VideoMetadataAdapters
        recordForElementAsync:element
                   completion:^(VideoMetadataRecord *metadata) {
                       id strongObject  = weakObject;
                       id strongElement = weakElement;
                       if (!strongElement || !metadata.videoID.length)
                           return;
                       if (strongObject &&
                           objc_getAssociatedObject(strongObject, NodeElementKey) != strongElement)
                           return;
                       if (strongObject)
                           BindMetadata(strongObject, strongElement, metadata);
                       else
                       {
                           DeArrowAssociateMetadata(strongElement, metadata);
                           ResolvePendingElementNodes(strongElement, metadata);
                       }
                   }];
}

static void CaptureNodeMetadata(id object)
{
    if (!IsMetadataNode(object) && !IsTextNode(object) && !IsImageNode(object))
        return;
    BrandingBinding     *binding  = DeArrowBindingForObject(object, YES);
    VideoMetadataRecord *metadata = DeArrowStoredMetadataForObject(object);
    if (metadata)
    {
        BindMetadata(object, objc_getAssociatedObject(object, NodeElementKey), metadata);
        return;
    }

    id element = NodeValue(object, @"element");
    if (element)
    {
        objc_setAssociatedObject(object, NodeElementKey, element,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        metadata = DeArrowStoredMetadataForObject(element);
        if (!metadata && (IsTextNode(object) || IsImageNode(object)))
            RememberPendingElementNode(element, object);
    }
    if (!metadata && (IsTextNode(object) || IsImageNode(object)))
        RememberPendingVisualNode(object);
    if (!metadata)
        metadata = DeArrowMetadataForNodeAncestor(object);
    if (!metadata && IsVideoNode(object))
        metadata = [VideoMetadataAdapters recordForNode:object];
    if (metadata)
        BindMetadata(object, element, metadata);

    if (IsTextNode(object))
        DeArrowCaptureTitleTextObject(object);

    if (!metadata.videoID.length && element && IsElementsNode(object) && !IsVideoNode(object) &&
        !binding.metadataAttempted)
    {
        RememberPendingElementNode(element, object);
        RequestElementMetadata(object, element);
    }
    if (!metadata.videoID.length && IsVideoNode(object) && !binding.metadataAttempted)
    {
        binding.metadataAttempted = YES;
        __weak id weakObject      = object;
        [VideoMetadataAdapters
            recordForNodeAsync:object
                    completion:^(VideoMetadataRecord *asyncMetadata) {
                        id strongObject = weakObject;
                        if (!strongObject || !asyncMetadata.videoID.length)
                            return;
                        BindMetadata(strongObject,
                                     objc_getAssociatedObject(strongObject, NodeElementKey),
                                     asyncMetadata);
                    }];
    }
}

static void CaptureNodeMetadataSafely(id object)
{
    @try
    {
        CaptureNodeMetadata(object);
    }
    @catch (__unused NSException *exception)
    {
    }
}

static void ResetElementMetadata(id object, id element)
{
    if (!object || !element || !IsMetadataNode(object))
        return;
    id               previousElement = objc_getAssociatedObject(object, NodeElementKey);
    BrandingBinding *binding         = DeArrowBindingForObject(object, NO);
    if (previousElement == element && binding && (binding.metadata || binding.metadataAttempted))
        return;
    objc_setAssociatedObject(object, NodeElementKey, element, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [VideoMetadataAdapters invalidateNode:object];
    DeArrowResetBindingForReuse(object);
    VideoMetadataRecord *metadata = DeArrowStoredMetadataForObject(element);
    if (!metadata)
        metadata = [VideoMetadataAdapters recordForElement:element];
    if (IsVideoNode(object))
        metadata = MergedMetadata(metadata, [VideoMetadataAdapters recordForNode:object]);
    if (metadata)
        BindMetadata(object, element, metadata);
    else if (IsElementOwnerNode(object))
    {
        RememberPendingElementNode(element, object);
        RequestElementMetadata(object, element);
    }
}

static IMP  CellElementSetterOriginal;
static BOOL CellElementHookInstalled;

static void HookedCellElementSetter(id object, SEL selector, id element)
{
    ((void (*)(id, SEL, id)) CellElementSetterOriginal)(object, selector, element);
    @try
    {
        ResetElementMetadata(object, element);
    }
    @catch (__unused NSException *exception)
    {
    }
}

static void __attribute__((unused)) InstallElementHook(Class targetClass)
{
    if (!targetClass)
        return;
    SEL    selector = @selector(setElement:);
    Method method   = class_getInstanceMethod(targetClass, selector);
    if (!method || method_getNumberOfArguments(method) != 3)
        return;
    char returnType[128]   = {0};
    char argumentType[128] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    method_getArgumentType(method, 2, argumentType, sizeof(argumentType));
    if (returnType[0] != 'v' || argumentType[0] != '@')
        return;
    if (CellElementHookInstalled)
        return;
    MSHookMessageEx(targetClass, selector, (IMP) HookedCellElementSetter,
                    &CellElementSetterOriginal);
    CellElementHookInstalled = CellElementSetterOriginal != NULL;
}

static void InstallNodeLoadHook(Class targetClass)
{
    if (!targetClass)
        return;
    SEL    selector = @selector(didLoad);
    Method method   = class_getInstanceMethod(targetClass, selector);
    if (!method || method_getNumberOfArguments(method) != 2)
        return;
    char returnType[128] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    if (returnType[0] != 'v')
        return;
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^(id object) {
            ((void (*)(id, SEL)) original)(object, command);
            CaptureNodeMetadataSafely(object);
        };
    });
}

static void InstallVideoEntryHook(Class targetClass)
{
    SEL    selector = NSSelectorFromString(@"setEntry:");
    Method method   = class_getInstanceMethod(targetClass, selector);
    if (!method || method_getNumberOfArguments(method) != 3)
        return;
    char returnType[128]   = {0};
    char argumentType[128] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    method_getArgumentType(method, 2, argumentType, sizeof(argumentType));
    if (returnType[0] != 'v' || argumentType[0] != '@')
        return;
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^(id object, id entry) {
            ((void (*)(id, SEL, id)) original)(object, command, entry);
            [VideoMetadataAdapters
                recordForEntryAsync:entry
                         completion:^(VideoMetadataRecord *metadata) {
                             if (metadata.videoID.length)
                                 BindMetadata(object, NodeValue(object, @"element"), metadata);
                         }];
        };
    });
}

void DeArrowInstallNodeIntegration(void)
{
    NSArray *classNames = @[
        @"ELMCellNode", @"YTVideoNode", @"YTVideoWithContextNode", @"YTGridVideoNode",
        @"YTShortsNode", @"YTShortsVideoNode", @"YTReelNode", @"YTReelItemNode", @"ELMTextNode",
        @"ELMImageNode", @"ASImageNode", @"ASNetworkImageNode"
    ];
    for (NSString *className in classNames)
    {
        Class targetClass = NSClassFromString(className);
        if (!targetClass)
            continue;
        if ([className isEqualToString:@"ELMCellNode"])
            continue;
        InstallNodeLoadHook(targetClass);
        if ([className isEqualToString:@"YTVideoWithContextNode"])
            InstallVideoEntryHook(targetClass);
    }
}
