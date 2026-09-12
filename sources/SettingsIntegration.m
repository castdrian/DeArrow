#import "SettingsIntegration.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "SettingsViewController.h"
#import "YouTube.h"

static const NSUInteger DeArrowSettingsCategory = 0x64617272;
static const NSUInteger DeArrowSettingsGroup = 0x64617270;
static void *SettingsManagerControllerKey = &SettingsManagerControllerKey;
static void *SettingsControllerManagerKey = &SettingsControllerManagerKey;
static void *SettingsNavigationTokenKey = &SettingsNavigationTokenKey;

static id SettingsObjectValue(id object, NSString *key) {
    if (!object || key.length == 0)
        return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static Class SettingsViewControllerClass(void) {
    return NSClassFromString(@"YTSettingsViewController");
}

static Class SettingsManagerClass(void) {
    return NSClassFromString(@"YTSettingsSectionItemManager");
}

static YTSettingsViewController *SettingsControllerFromObject(id object) {
    Class settingsClass = SettingsViewControllerClass();
    if (settingsClass && [object isKindOfClass:settingsClass])
        return object;
    return nil;
}

static BOOL ViewControllerContains(UIViewController *root, UIViewController *target, NSUInteger depth) {
    if (!root || !target || depth > 12)
        return NO;
    if (root == target)
        return YES;
    if (root.presentedViewController && !root.presentedViewController.isBeingDismissed &&
        ViewControllerContains(root.presentedViewController, target, depth + 1))
        return YES;
    for (UIViewController *child in root.childViewControllers) {
        if (ViewControllerContains(child, target, depth + 1))
            return YES;
    }
    return NO;
}

static UINavigationController *NavigationControllerContaining(UIViewController *root,
                                                               UIViewController *target,
                                                               NSUInteger depth) {
    if (!root || !target || depth > 8)
        return nil;
    if ([root isKindOfClass:[UINavigationController class]] && ViewControllerContains(root, target, 0))
        return (UINavigationController *)root;
    if (root.presentedViewController && !root.presentedViewController.isBeingDismissed) {
        UINavigationController *navigationController = NavigationControllerContaining(root.presentedViewController,
                                                                                         target,
                                                                                         depth + 1);
        if (navigationController)
            return navigationController;
    }
    for (UIViewController *child in root.childViewControllers) {
        UINavigationController *navigationController = NavigationControllerContaining(child, target, depth + 1);
        if (navigationController)
            return navigationController;
    }
    return nil;
}

static UINavigationController *NavigationControllerForSettingsController(UIViewController *controller) {
    if (!controller)
        return nil;
    if ([controller isKindOfClass:[UINavigationController class]])
        return (UINavigationController *)controller;
    if (controller.navigationController)
        return controller.navigationController;
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        UINavigationController *navigationController = NavigationControllerContaining(window.rootViewController,
                                                                                         controller,
                                                                                         0);
        if (navigationController)
            return navigationController;
    }
    return nil;
}

static YTSettingsViewController *SettingsControllerInViewController(UIViewController *controller,
                                                                     NSUInteger depth) {
    if (!controller || depth > 12)
        return nil;
    YTSettingsViewController *settingsController = SettingsControllerFromObject(controller);
    if (settingsController)
        return settingsController;
    if (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) {
        settingsController = SettingsControllerInViewController(controller.presentedViewController, depth + 1);
        if (settingsController)
            return settingsController;
    }
    if ([controller isKindOfClass:[UINavigationController class]]) {
        for (UIViewController *child in ((UINavigationController *)controller).viewControllers) {
            settingsController = SettingsControllerInViewController(child, depth + 1);
            if (settingsController)
                return settingsController;
        }
    }
    if ([controller isKindOfClass:[UISplitViewController class]]) {
        for (UIViewController *child in ((UISplitViewController *)controller).viewControllers) {
            settingsController = SettingsControllerInViewController(child, depth + 1);
            if (settingsController)
                return settingsController;
        }
    }
    for (UIViewController *child in controller.childViewControllers) {
        settingsController = SettingsControllerInViewController(child, depth + 1);
        if (settingsController)
            return settingsController;
    }
    return nil;
}

static YTSettingsViewController *SettingsControllerForManager(YTSettingsSectionItemManager *manager) {
    if (!manager)
        return nil;
    YTSettingsViewController *controller = objc_getAssociatedObject(manager, SettingsManagerControllerKey);
    if (controller)
        return controller;
    for (NSString *key in @[@"_dataDelegate", @"_settingsViewControllerDelegate", @"parentResponder"]) {
        id candidate = SettingsObjectValue(manager, key);
        controller = SettingsControllerFromObject(candidate);
        if (controller)
            return controller;
        id responder = candidate;
        for (NSUInteger depth = 0; responder && depth < 8; depth++) {
            controller = SettingsControllerFromObject(responder);
            if (controller)
                return controller;
            if (![responder respondsToSelector:@selector(nextResponder)])
                break;
            responder = [responder nextResponder];
        }
    }
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        controller = SettingsControllerInViewController(window.rootViewController, 0);
        if (controller)
            return controller;
    }
    return nil;
}

static YTSettingsSectionItemManager *SettingsManagerForController(YTSettingsViewController *controller) {
    if (!controller)
        return nil;
    YTSettingsSectionItemManager *manager = objc_getAssociatedObject(controller, SettingsControllerManagerKey);
    if (!manager)
        manager = objc_getAssociatedObject(controller.navigationController, SettingsControllerManagerKey);
    if (!manager) {
        Class managerClass = SettingsManagerClass();
        for (NSString *key in @[@"_sectionItemManager", @"sectionItemManager"]) {
            id candidate = SettingsObjectValue(controller, key);
            if (!managerClass || [candidate isKindOfClass:managerClass]) {
                manager = candidate;
                if (manager)
                    break;
            }
        }
    }
    if (manager) {
        objc_setAssociatedObject(controller, SettingsControllerManagerKey, manager, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(manager, SettingsManagerControllerKey, controller, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return manager;
}

static void AssociateSettingsManager(YTSettingsViewController *controller, YTSettingsSectionItemManager *manager) {
    if (!controller || !manager)
        return;
    objc_setAssociatedObject(controller, SettingsControllerManagerKey, manager, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(manager, SettingsManagerControllerKey, controller, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UINavigationController *navigationController = NavigationControllerForSettingsController(controller);
    if (navigationController)
        objc_setAssociatedObject(navigationController, SettingsControllerManagerKey, manager, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSNumber *SettingsCategoryValue(id object, NSUInteger depth) {
    if (!object || depth > 3)
        return nil;
    for (NSString *key in @[@"category", @"categoryID", @"categoryId", @"settingsCategory"]) {
        id value = SettingsObjectValue(object, key);
        if ([value respondsToSelector:@selector(unsignedIntegerValue)])
            return @([value unsignedIntegerValue]);
    }
    for (NSString *key in @[@"model", @"content", @"navigationEndpoint", @"endpoint"]) {
        NSNumber *value = SettingsCategoryValue(SettingsObjectValue(object, key), depth + 1);
        if (value)
            return value;
    }
    return nil;
}

static BOOL IsDeArrowSettingsCandidate(UIViewController *candidate) {
    if (!candidate)
        return NO;
    Class customClass = NSClassFromString(@"DeArrowSettingsViewController");
    if (customClass && [candidate isKindOfClass:customClass])
        return NO;
    NSNumber *category = SettingsCategoryValue(candidate, 0);
    if (!category)
        category = SettingsCategoryValue(SettingsObjectValue(candidate, @"content"), 0);
    return category.unsignedIntegerValue == DeArrowSettingsCategory;
}

static UIViewController *CreateCustomSettingsDestination(YTSettingsViewController *settingsController) {
    UIViewController *custom = CreateDeArrowSettingsViewController();
    YTSettingsSectionItemManager *manager = SettingsManagerForController(settingsController);
    if (manager)
        objc_setAssociatedObject(custom, SettingsControllerManagerKey, manager, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return custom;
}

static BOOL PushCustomSettings(YTSettingsViewController *settingsController, BOOL animated) {
    UINavigationController *navigationController = NavigationControllerForSettingsController(settingsController);
    UIViewController *custom = CreateCustomSettingsDestination(settingsController);
    if (!navigationController || !custom)
        return NO;
    [navigationController pushViewController:custom animated:animated];
    return YES;
}

static void ArmNavigationToken(YTSettingsViewController *controller) {
    if (!controller)
        return;
    NSNumber *token = @YES;
    objc_setAssociatedObject(controller, SettingsNavigationTokenKey, token, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (objc_getAssociatedObject(controller, SettingsNavigationTokenKey) == token)
            objc_setAssociatedObject(controller, SettingsNavigationTokenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

static BOOL ConsumeNavigationToken(YTSettingsViewController *controller) {
    if (!controller || !objc_getAssociatedObject(controller, SettingsNavigationTokenKey))
        return NO;
    objc_setAssociatedObject(controller, SettingsNavigationTokenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

static YTSettingsSectionItem *MakeSectionItem(YTSettingsViewController *controller) {
    Class itemClass = NSClassFromString(@"YTSettingsSectionItem");
    if (!itemClass)
        return nil;
    __weak YTSettingsViewController *weakController = controller;
    BOOL (^selectBlock)(YTSettingsCell *, NSUInteger) = ^BOOL(__unused YTSettingsCell *cell,
                                                               __unused NSUInteger index) {
        YTSettingsViewController *strongController = weakController;
        return strongController ? PushCustomSettings(strongController, YES) : NO;
    };
    SEL compactSelector = @selector(itemWithTitle:accessibilityIdentifier:detailTextBlock:selectBlock:);
    if ([itemClass respondsToSelector:compactSelector]) {
        id (*message)(id, SEL, NSString *, NSString *, id, id) = (id (*)(id, SEL, NSString *, NSString *, id, id))objc_msgSend;
        return message(itemClass, compactSelector, @"DeArrow", @"dev.adrian.dearrow.settings", nil, selectBlock);
    }
    SEL detailedSelector = @selector(itemWithTitle:titleDescription:accessibilityIdentifier:detailTextBlock:selectBlock:);
    if ([itemClass respondsToSelector:detailedSelector]) {
        id (*message)(id, SEL, NSString *, NSString *, NSString *, id, id) = (id (*)(id, SEL, NSString *, NSString *, NSString *, id, id))objc_msgSend;
        return message(itemClass, detailedSelector, @"DeArrow", nil, @"dev.adrian.dearrow.settings", nil, selectBlock);
    }
    return nil;
}

static void ConfigureSettingsSection(YTSettingsSectionItemManager *manager) {
    YTSettingsViewController *controller = SettingsControllerForManager(manager);
    YTSettingsSectionItem *item = MakeSectionItem(controller);
    if (!controller || !item)
        return;
    AssociateSettingsManager(controller, manager);
    NSMutableArray *items = [NSMutableArray arrayWithObject:item];
    SEL modernSelector = @selector(setSectionItems:forCategory:title:icon:titleDescription:headerHidden:);
    if ([controller respondsToSelector:modernSelector]) {
        void (*message)(id, SEL, NSMutableArray *, NSInteger, NSString *, YTIIcon *, NSString *, BOOL) = (void (*)(id, SEL, NSMutableArray *, NSInteger, NSString *, YTIIcon *, NSString *, BOOL))objc_msgSend;
        message(controller, modernSelector, items, DeArrowSettingsCategory, @"DeArrow", nil, nil, NO);
        return;
    }
    SEL legacySelector = @selector(setSectionItems:forCategory:title:titleDescription:headerHidden:);
    if ([controller respondsToSelector:legacySelector]) {
        void (*message)(id, SEL, NSMutableArray *, NSInteger, NSString *, NSString *, BOOL) = (void (*)(id, SEL, NSMutableArray *, NSInteger, NSString *, NSString *, BOOL))objc_msgSend;
        message(controller, legacySelector, items, DeArrowSettingsCategory, @"DeArrow", nil, NO);
    }
}

static void InstallInstanceHook(Class targetClass, SEL selector, id (^builder)(IMP, SEL)) {
    Method inheritedMethod = class_getInstanceMethod(targetClass, selector);
    if (!inheritedMethod)
        return;
    class_addMethod(targetClass, selector, method_getImplementation(inheritedMethod), method_getTypeEncoding(inheritedMethod));
    Method method = class_getInstanceMethod(targetClass, selector);
    IMP original = method_getImplementation(method);
    method_setImplementation(method, imp_implementationWithBlock(builder(original, selector)));
}

static void InstallClassHook(Class targetClass, SEL selector, id (^builder)(IMP, SEL)) {
    Class metaClass = object_getClass(targetClass);
    Method inheritedMethod = class_getInstanceMethod(metaClass, selector);
    if (!inheritedMethod)
        return;
    class_addMethod(metaClass, selector, method_getImplementation(inheritedMethod), method_getTypeEncoding(inheritedMethod));
    Method method = class_getInstanceMethod(metaClass, selector);
    IMP original = method_getImplementation(method);
    method_setImplementation(method, imp_implementationWithBlock(builder(original, selector)));
}

static void InstallTweakCategoryHook(Class groupClass) {
    SEL selector = @selector(tweaks);
    Class metaClass = object_getClass(groupClass);
    Method method = class_getInstanceMethod(metaClass, selector);
    if (method) {
        IMP original = method_getImplementation(method);
        id replacement = ^id(id object, SEL command) {
            NSMutableArray *categories = [NSMutableArray array];
            NSArray *existing = ((id (*)(id, SEL))original)(object, command);
            if ([existing isKindOfClass:[NSArray class]])
                [categories addObjectsFromArray:existing];
            if (![categories containsObject:@(DeArrowSettingsCategory)])
                [categories addObject:@(DeArrowSettingsCategory)];
            return categories;
        };
        method_setImplementation(method, imp_implementationWithBlock(replacement));
        return;
    }
    id replacement = ^id(__unused id object, __unused SEL command) {
        return [NSMutableArray arrayWithObject:@(DeArrowSettingsCategory)];
    };
    class_addMethod(metaClass, selector, imp_implementationWithBlock(replacement), "@@:");
}

static void InstallSettingsNavigationHooks(Class targetClass) {
    InstallInstanceHook(targetClass, @selector(pushViewController:), ^id(IMP original, SEL selector) {
        return ^(id object, SEL command, UIViewController *viewController) {
            YTSettingsViewController *settingsController = SettingsControllerFromObject(object);
            if (!settingsController && [object isKindOfClass:[UINavigationController class]])
                settingsController = SettingsControllerInViewController(((UINavigationController *)object).visibleViewController, 0);
            UIViewController *custom = nil;
            if (settingsController && (ConsumeNavigationToken(settingsController) || IsDeArrowSettingsCandidate(viewController)))
                custom = CreateCustomSettingsDestination(settingsController);
            ((void (*)(id, SEL, UIViewController *))original)(object, command, custom ?: viewController);
        };
    });
    InstallInstanceHook(targetClass, @selector(pushViewController:animated:), ^id(IMP original, SEL selector) {
        return ^(id object, SEL command, UIViewController *viewController, BOOL animated) {
            YTSettingsViewController *settingsController = SettingsControllerFromObject(object);
            if (!settingsController && [object isKindOfClass:[UINavigationController class]])
                settingsController = SettingsControllerInViewController(((UINavigationController *)object).visibleViewController, 0);
            UIViewController *custom = nil;
            if (settingsController && (ConsumeNavigationToken(settingsController) || IsDeArrowSettingsCandidate(viewController)))
                custom = CreateCustomSettingsDestination(settingsController);
            ((void (*)(id, SEL, UIViewController *, BOOL))original)(object, command, custom ?: viewController, animated);
        };
    });
    InstallInstanceHook(targetClass, @selector(showOrPushViewController:), ^id(IMP original, SEL selector) {
        return ^(id object, SEL command, UIViewController *viewController) {
            YTSettingsViewController *settingsController = SettingsControllerFromObject(object);
            if (!settingsController && [object isKindOfClass:[UINavigationController class]])
                settingsController = SettingsControllerInViewController(((UINavigationController *)object).visibleViewController, 0);
            UIViewController *custom = nil;
            if (settingsController && (ConsumeNavigationToken(settingsController) || IsDeArrowSettingsCandidate(viewController)))
                custom = CreateCustomSettingsDestination(settingsController);
            ((void (*)(id, SEL, UIViewController *))original)(object, command, custom ?: viewController);
        };
    });
    InstallInstanceHook(targetClass, @selector(showViewController:sender:), ^id(IMP original, SEL selector) {
        return ^(id object, SEL command, UIViewController *viewController, id sender) {
            YTSettingsViewController *settingsController = SettingsControllerFromObject(object);
            if (!settingsController && [object isKindOfClass:[UINavigationController class]])
                settingsController = SettingsControllerInViewController(((UINavigationController *)object).visibleViewController, 0);
            UIViewController *custom = nil;
            if (settingsController && (ConsumeNavigationToken(settingsController) || IsDeArrowSettingsCandidate(viewController)))
                custom = CreateCustomSettingsDestination(settingsController);
            ((void (*)(id, SEL, UIViewController *, id))original)(object, command, custom ?: viewController, sender);
        };
    });
    InstallInstanceHook(targetClass, @selector(setViewControllers:), ^id(IMP original, SEL selector) {
        return ^(id object, SEL command, NSArray<UIViewController *> *viewControllers) {
            UINavigationController *navigationController = [object isKindOfClass:[UINavigationController class]] ? object : nil;
            YTSettingsViewController *settingsController = navigationController ? SettingsControllerInViewController(navigationController, 0) : nil;
            NSMutableArray *replacement = [viewControllers mutableCopy];
            if (settingsController) {
                NSUInteger settingsIndex = [replacement indexOfObjectIdenticalTo:settingsController];
                if (settingsIndex != NSNotFound && settingsIndex + 1 < replacement.count && IsDeArrowSettingsCandidate(replacement[settingsIndex + 1]))
                    replacement[settingsIndex + 1] = CreateCustomSettingsDestination(settingsController);
            }
            ((void (*)(id, SEL, NSArray<UIViewController *> *))original)(object, command, replacement ?: viewControllers);
        };
    });
    InstallInstanceHook(targetClass, @selector(setViewControllers:animated:), ^id(IMP original, SEL selector) {
        return ^(id object, SEL command, NSArray<UIViewController *> *viewControllers, BOOL animated) {
            UINavigationController *navigationController = [object isKindOfClass:[UINavigationController class]] ? object : nil;
            YTSettingsViewController *settingsController = navigationController ? SettingsControllerInViewController(navigationController, 0) : nil;
            NSMutableArray *replacement = [viewControllers mutableCopy];
            if (settingsController) {
                NSUInteger settingsIndex = [replacement indexOfObjectIdenticalTo:settingsController];
                if (settingsIndex != NSNotFound && settingsIndex + 1 < replacement.count && IsDeArrowSettingsCandidate(replacement[settingsIndex + 1]))
                    replacement[settingsIndex + 1] = CreateCustomSettingsDestination(settingsController);
            }
            ((void (*)(id, SEL, NSArray<UIViewController *> *, BOOL))original)(object, command, replacement ?: viewControllers, animated);
        };
    });
}

void DeArrowInstallSettingsIntegration(void) {
    Class groupClass = NSClassFromString(@"YTSettingsGroupData");
    if (groupClass) {
        InstallTweakCategoryHook(groupClass);
        InstallInstanceHook(groupClass, @selector(orderedCategories), ^id(IMP original, SEL selector) {
            return ^id(id object, SEL command) {
                if ([object respondsToSelector:@selector(type)] && [(YTSettingsGroupData *)object type] == DeArrowSettingsGroup)
                    return @[@(DeArrowSettingsCategory)];
                return ((id (*)(id, SEL))original)(object, command);
            };
        });
        InstallInstanceHook(groupClass, @selector(orderedCategoriesForGroupType:), ^id(IMP original, SEL selector) {
            return ^id(id object, SEL command, NSUInteger type) {
                if (type == DeArrowSettingsGroup)
                    return @[@(DeArrowSettingsCategory)];
                return ((id (*)(id, SEL, NSUInteger))original)(object, command, type);
            };
        });
        InstallInstanceHook(groupClass, @selector(titleForSettingGroupType:), ^id(IMP original, SEL selector) {
            return ^id(id object, SEL command, NSUInteger type) {
                if (type == DeArrowSettingsGroup)
                    return nil;
                return ((id (*)(id, SEL, NSUInteger))original)(object, command, type);
            };
        });
    }
    Class groupPresentationClass = NSClassFromString(@"YTAppSettingsGroupPresentationData");
    if (groupPresentationClass) {
        InstallClassHook(groupPresentationClass, @selector(orderedGroups), ^id(IMP original, SEL selector) {
            return ^id(id object, SEL command) {
                NSArray *groups = ((id (*)(id, SEL))original)(object, command);
                for (id group in groups) {
                    if ([group respondsToSelector:@selector(type)] && [(YTSettingsGroupData *)group type] == DeArrowSettingsGroup)
                        return groups;
                }
                Class settingsGroupClass = NSClassFromString(@"YTSettingsGroupData");
                if (!settingsGroupClass)
                    return groups;
                NSMutableArray *result = [groups mutableCopy] ?: [NSMutableArray array];
                [result insertObject:[[settingsGroupClass alloc] initWithGroupType:DeArrowSettingsGroup] atIndex:0];
                return result.copy;
            };
        });
    }
    Class managerClass = SettingsManagerClass();
    if (managerClass) {
        InstallInstanceHook(managerClass, @selector(initWithParentResponder:controllerDelegate:dataDelegate:settingsViewControllerDelegate:), ^id(IMP original, SEL selector) {
            return ^id(id object, SEL command, id parentResponder, id controllerDelegate, id dataDelegate, id settingsViewControllerDelegate) {
                id result = ((id (*)(id, SEL, id, id, id, id))original)(object, command, parentResponder, controllerDelegate, dataDelegate, settingsViewControllerDelegate);
                YTSettingsViewController *controller = SettingsControllerFromObject(dataDelegate) ?: SettingsControllerFromObject(settingsViewControllerDelegate) ?: SettingsControllerFromObject(parentResponder);
                if (result && controller)
                    AssociateSettingsManager(controller, result);
                return result;
            };
        });
        InstallInstanceHook(managerClass, @selector(updateSectionForCategory:withEntry:), ^id(IMP original, SEL selector) {
            return ^(id object, SEL command, NSUInteger category, id entry) {
                if (category == DeArrowSettingsCategory) {
                    ConfigureSettingsSection(object);
                    return;
                }
                ((void (*)(id, SEL, NSUInteger, id))original)(object, command, category, entry);
            };
        });
    }
    Class settingsClass = SettingsViewControllerClass();
    if (settingsClass) {
        InstallInstanceHook(settingsClass, @selector(setSectionItems:forCategory:title:icon:titleDescription:headerHidden:), ^id(IMP original, SEL selector) {
            return ^(id object, SEL command, NSMutableArray *items, NSInteger category, NSString *title, YTIIcon *icon, NSString *description, BOOL headerHidden) {
                ((void (*)(id, SEL, NSMutableArray *, NSInteger, NSString *, YTIIcon *, NSString *, BOOL))original)(object, command, items, category, title, icon, description, headerHidden);
                if (category == DeArrowSettingsCategory)
                    SettingsManagerForController(object);
            };
        });
        InstallInstanceHook(settingsClass, @selector(setSectionItems:forCategory:title:titleDescription:headerHidden:), ^id(IMP original, SEL selector) {
            return ^(id object, SEL command, NSMutableArray *items, NSInteger category, NSString *title, NSString *description, BOOL headerHidden) {
                ((void (*)(id, SEL, NSMutableArray *, NSInteger, NSString *, NSString *, BOOL))original)(object, command, items, category, title, description, headerHidden);
                if (category == DeArrowSettingsCategory)
                    SettingsManagerForController(object);
            };
        });
        InstallInstanceHook(settingsClass, @selector(sendSettingsNavigationEndpointForCategory:), ^id(IMP original, SEL selector) {
            return ^(id object, SEL command, NSUInteger category) {
                if (category == DeArrowSettingsCategory) {
                    if (!PushCustomSettings(object, YES))
                        ArmNavigationToken(object);
                    return;
                }
                ((void (*)(id, SEL, NSUInteger))original)(object, command, category);
            };
        });
        InstallInstanceHook(settingsClass, @selector(didReceiveDrillDownItem:), ^id(IMP original, SEL selector) {
            return ^(id object, SEL command, id item) {
                if (SettingsCategoryValue(item, 0).unsignedIntegerValue == DeArrowSettingsCategory) {
                    if (!PushCustomSettings(object, YES))
                        ArmNavigationToken(object);
                    return;
                }
                ((void (*)(id, SEL, id))original)(object, command, item);
            };
        });
        InstallSettingsNavigationHooks(settingsClass);
    }
    Class navigationClass = NSClassFromString(@"UINavigationController");
    if (navigationClass)
        InstallSettingsNavigationHooks(navigationClass);
    Class youtubeNavigationClass = NSClassFromString(@"YTNavigationController");
    if (youtubeNavigationClass)
        InstallSettingsNavigationHooks(youtubeNavigationClass);
}
