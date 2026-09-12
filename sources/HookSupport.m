#import "HookSupport.h"

static NSMutableSet *DeArrowInstalledHooks(void) {
    static NSMutableSet *hooks;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hooks = [NSMutableSet set];
    });
    return hooks;
}

static NSString *DeArrowHookKey(Class targetClass, SEL selector, BOOL classMethod) {
    return [NSString stringWithFormat:@"%p:%@:%@", targetClass, NSStringFromSelector(selector), classMethod ? @"class" : @"instance"];
}

static BOOL DeArrowInstallHook(Class targetClass, SEL selector, DeArrowHookBuilder builder, BOOL classMethod) {
    if (!targetClass || !selector || !builder)
        return NO;
    Class methodClass = classMethod ? object_getClass(targetClass) : targetClass;
    if (!methodClass)
        return NO;
    NSString *key = DeArrowHookKey(targetClass, selector, classMethod);
    @synchronized (DeArrowInstalledHooks()) {
        if ([DeArrowInstalledHooks() containsObject:key])
            return NO;
        Method inheritedMethod = class_getInstanceMethod(methodClass, selector);
        if (!inheritedMethod)
            return NO;
        class_addMethod(methodClass,
                        selector,
                        method_getImplementation(inheritedMethod),
                        method_getTypeEncoding(inheritedMethod));
        Method method = class_getInstanceMethod(methodClass, selector);
        if (!method)
            return NO;
        id replacement = builder(method_getImplementation(method), selector);
        if (!replacement)
            return NO;
        IMP replacementImplementation = imp_implementationWithBlock(replacement);
        if (!replacementImplementation)
            return NO;
        method_setImplementation(method, replacementImplementation);
        [DeArrowInstalledHooks() addObject:key];
        return YES;
    }
}

BOOL DeArrowInstallInstanceHook(Class targetClass, SEL selector, DeArrowHookBuilder builder) {
    return DeArrowInstallHook(targetClass, selector, builder, NO);
}

BOOL DeArrowInstallClassHook(Class targetClass, SEL selector, DeArrowHookBuilder builder) {
    return DeArrowInstallHook(targetClass, selector, builder, YES);
}
