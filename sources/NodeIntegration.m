#import "NodeIntegration.h"

#import <objc/runtime.h>

#import "IntegrationSupport.h"
#import "Metadata.h"

static NSArray *NodeChildren(id object) {
    if (!object || ![object respondsToSelector:NSSelectorFromString(@"yogaChildren")])
        return nil;
    @try {
        id children = [object valueForKey:@"yogaChildren"];
        return [children isKindOfClass:[NSArray class]] ? children : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static void ResetNodeBinding(id object, NSUInteger depth) {
    if (!object || depth > 12)
        return;
    BrandingBinding *binding = DeArrowBindingForObject(object, NO);
    if (binding) {
        DeArrowCancelBinding(object);
        binding.metadata = nil;
        binding.metadataAttempted = NO;
        binding.originalTitle = nil;
        binding.originalImage = nil;
    }
    for (id child in NodeChildren(object))
        ResetNodeBinding(child, depth + 1);
}

static void AssociateNodeMetadata(id object, VideoMetadataRecord *metadata, NSUInteger depth) {
    if (!object || !metadata || depth > 12)
        return;
    DeArrowAssociateMetadata(object, metadata);
    for (id child in NodeChildren(object))
        AssociateNodeMetadata(child, metadata, depth + 1);
}

static void InstallElementHook(Class targetClass) {
    SEL selector = @selector(setElement:);
    Method method = class_getInstanceMethod(targetClass, selector);
    if (!method)
        return;
    class_addMethod(targetClass, selector, method_getImplementation(method), method_getTypeEncoding(method));
    method = class_getInstanceMethod(targetClass, selector);
    IMP original = method_getImplementation(method);
    id replacement = ^(id object, SEL command, id element) {
        ((void (*)(id, SEL, id))original)(object, command, element);
        ResetNodeBinding(object, 0);
        VideoMetadataRecord *metadata = [VideoMetadataAdapters recordForNode:object];
        if (metadata)
            AssociateNodeMetadata(object, metadata, 0);
        else
            DeArrowBindingForObject(object, YES).metadataAttempted = YES;
    };
    method_setImplementation(method, imp_implementationWithBlock(replacement));
}

static void InstallNodeAdditionHook(Class targetClass, SEL selector, BOOL indexed) {
    Method method = class_getInstanceMethod(targetClass, selector);
    if (!method)
        return;
    class_addMethod(targetClass, selector, method_getImplementation(method), method_getTypeEncoding(method));
    method = class_getInstanceMethod(targetClass, selector);
    IMP original = method_getImplementation(method);
    if (indexed) {
        id replacement = ^(id object, SEL command, id child, NSUInteger index) {
            ((void (*)(id, SEL, id, NSUInteger))original)(object, command, child, index);
            DeArrowPropagateMetadata(object, child);
        };
        method_setImplementation(method, imp_implementationWithBlock(replacement));
    } else {
        id replacement = ^(id object, SEL command, id child) {
            ((void (*)(id, SEL, id))original)(object, command, child);
            DeArrowPropagateMetadata(object, child);
        };
        method_setImplementation(method, imp_implementationWithBlock(replacement));
    }
}

static void InstallNodeLoadHook(Class targetClass) {
    SEL selector = @selector(didLoad);
    Method method = class_getInstanceMethod(targetClass, selector);
    if (!method)
        return;
    class_addMethod(targetClass, selector, method_getImplementation(method), method_getTypeEncoding(method));
    method = class_getInstanceMethod(targetClass, selector);
    IMP original = method_getImplementation(method);
    id replacement = ^(id object, SEL command) {
        ((void (*)(id, SEL))original)(object, command);
        if (!DeArrowStoredMetadataForObject(object)) {
            VideoMetadataRecord *metadata = [VideoMetadataAdapters recordForNode:object];
            if (metadata)
                DeArrowAssociateMetadata(object, metadata);
        }
    };
    method_setImplementation(method, imp_implementationWithBlock(replacement));
}

void DeArrowInstallNodeIntegration(void) {
    Class cellNodeClass = NSClassFromString(@"ELMCellNode");
    if (!cellNodeClass)
        cellNodeClass = NSClassFromString(@"YTVideoNode");
    if (cellNodeClass) {
        InstallElementHook(cellNodeClass);
        InstallNodeLoadHook(cellNodeClass);
    }
    Class displayNodeClass = NSClassFromString(@"ASDisplayNode");
    if (displayNodeClass) {
        InstallNodeAdditionHook(displayNodeClass, @selector(addSubnode:), NO);
        InstallNodeAdditionHook(displayNodeClass, @selector(insertYogaChild:atIndex:), YES);
    }
}
