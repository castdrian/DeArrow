#import <Foundation/Foundation.h>
#import <objc/runtime.h>

typedef id (^DeArrowHookBuilder)(IMP original, SEL selector);

BOOL DeArrowInstallInstanceHook(Class targetClass, SEL selector, DeArrowHookBuilder builder);
BOOL DeArrowInstallClassHook(Class targetClass, SEL selector, DeArrowHookBuilder builder);
