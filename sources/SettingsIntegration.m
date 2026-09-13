#import "SettingsIntegration.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "HookSupport.h"
#import "SettingsViewController.h"
#import "YouTube.h"

static const NSUInteger DeArrowSettingsCategory = 0x64617272;
static const NSUInteger DeArrowSettingsGroup = 0x64617270;
static void *SettingsManagerControllerKey = &SettingsManagerControllerKey;
static void *SettingsControllerManagerKey = &SettingsControllerManagerKey;
static void *NestedCustomSettingsKey = &NestedCustomSettingsKey;

static id SettingsIvarObject(id object, const char *name);

static id SettingsObjectValue(id object, NSString *key) {
    if (!object || key.length == 0)
        return nil;
    @try {
        id value = [object valueForKey:key];
        if (value)
            return value;
    } @catch (__unused NSException *exception) {
    }
    return SettingsIvarObject(object, key.UTF8String);
}

static id SettingsIvarObject(id object, const char *name) {
    if (!object || !name)
        return nil;
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    const char *encoding = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if (!encoding || encoding[0] != '@')
        return nil;
    return object_getIvar(object, ivar);
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

static YTSettingsSectionItemManager *SettingsManagerForController(YTSettingsViewController *controller) {
    if (!controller)
        return nil;
    YTSettingsSectionItemManager *manager = objc_getAssociatedObject(controller, SettingsControllerManagerKey);
    if (!manager)
        manager = objc_getAssociatedObject(controller.navigationController, SettingsControllerManagerKey);
    if (!manager) {
        Class managerClass = SettingsManagerClass();
        for (NSString *key in @[@"_sectionItemManager", @"sectionItemManager"]) {
            id candidate = SettingsObjectValue(controller, key) ?: SettingsIvarObject(controller, key.UTF8String);
            if (candidate && (!managerClass || [candidate isKindOfClass:managerClass])) {
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

static BOOL PushCustomSettings(YTSettingsViewController *settingsController, BOOL animated);

static YTSettingsSectionItem *MakeSettingsItem(YTSettingsViewController *controller) {
    Class itemClass = NSClassFromString(@"YTSettingsSectionItem");
    if (!itemClass)
        return nil;
    __weak YTSettingsViewController *weakController = controller;
    BOOL (^selectBlock)(YTSettingsCell *, NSUInteger) = ^BOOL(__unused YTSettingsCell *cell, __unused NSUInteger index) {
        YTSettingsViewController *strongController = weakController;
        return strongController ? PushCustomSettings(strongController, YES) : NO;
    };
    SEL modernSelector = @selector(itemWithTitle:titleDescription:accessibilityIdentifier:detailTextBlock:selectBlock:settingItemId:);
    if ([itemClass respondsToSelector:modernSelector]) {
        id (*message)(id, SEL, NSString *, NSString *, NSString *, id, id, NSUInteger) = (id (*)(id, SEL, NSString *, NSString *, NSString *, id, id, NSUInteger))objc_msgSend;
        return message(itemClass, modernSelector, @"DeArrow", nil, @"dev.adrian.dearrow.settings", nil, selectBlock, DeArrowSettingsCategory);
    }
    SEL legacySelector = @selector(itemWithTitle:titleDescription:accessibilityIdentifier:detailTextBlock:selectBlock:);
    if ([itemClass respondsToSelector:legacySelector]) {
        id (*message)(id, SEL, NSString *, NSString *, NSString *, id, id) = (id (*)(id, SEL, NSString *, NSString *, NSString *, id, id))objc_msgSend;
        return message(itemClass, legacySelector, @"DeArrow", nil, @"dev.adrian.dearrow.settings", nil, selectBlock);
    }
    return nil;
}

static void ConfigureSettingsSectionForController(YTSettingsViewController *controller) {
    if (!controller)
        return;
    YTSettingsSectionItemManager *manager = SettingsManagerForController(controller);
    YTSettingsSectionItem *item = MakeSettingsItem(controller);
    if (!item)
        return;
    if (manager) {
        objc_setAssociatedObject(controller, SettingsControllerManagerKey, manager, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(manager, SettingsManagerControllerKey, controller, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSMutableArray *items = [NSMutableArray arrayWithObject:item];
    YTIIcon *icon = [NSClassFromString(@"YTIIcon") new];
    if ([icon respondsToSelector:@selector(setIconType:)])
        icon.iconType = 193;
    SEL modernSelector = @selector(setSectionItems:forCategory:title:icon:titleDescription:headerHidden:);
    if ([controller respondsToSelector:modernSelector]) {
        void (*message)(id, SEL, NSMutableArray *, NSInteger, NSString *, YTIIcon *, NSString *, BOOL) = (void (*)(id, SEL, NSMutableArray *, NSInteger, NSString *, YTIIcon *, NSString *, BOOL))objc_msgSend;
        message(controller, modernSelector, items, DeArrowSettingsCategory, @"DeArrow", icon, nil, NO);
        return;
    }
    SEL legacySelector = @selector(setSectionItems:forCategory:title:titleDescription:headerHidden:);
    if ([controller respondsToSelector:legacySelector]) {
        void (*message)(id, SEL, NSMutableArray *, NSInteger, NSString *, NSString *, BOOL) = (void (*)(id, SEL, NSMutableArray *, NSInteger, NSString *, NSString *, BOOL))objc_msgSend;
        message(controller, legacySelector, items, DeArrowSettingsCategory, @"DeArrow", nil, NO);
    }
}

static void __attribute__((unused)) ConfigureSettingsSection(YTSettingsSectionItemManager *manager) {
    YTSettingsViewController *controller = SettingsControllerForManager(manager);
    if (controller)
        ConfigureSettingsSectionForController(controller);
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
    NSString *description = [object description];
    NSRange marker = [description rangeOfString:@"category_id:"];
    if (marker.location != NSNotFound) {
        NSString *suffix = [description substringFromIndex:NSMaxRange(marker)];
        NSScanner *scanner = [NSScanner scannerWithString:suffix];
        unsigned long long category = 0;
        if ([scanner scanUnsignedLongLong:&category])
            return @(category);
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

static BOOL SettingsCandidateInHierarchy(UIViewController *controller, NSUInteger depth);

static BOOL IsDeArrowSettingsDestination(UIViewController *candidate) {
    if (!candidate)
        return NO;
    if (SettingsCandidateInHierarchy(candidate, 0))
        return YES;
    return [candidate.title isEqualToString:@"DeArrow"] ||
        [candidate.navigationItem.title isEqualToString:@"DeArrow"];
}

static UIViewController *CreateCustomSettingsDestination(YTSettingsViewController *settingsController) {
    UIViewController *custom = CreateDeArrowSettingsViewController();
    YTSettingsSectionItemManager *manager = SettingsManagerForController(settingsController);
    if (manager)
        objc_setAssociatedObject(custom, SettingsControllerManagerKey, manager, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return custom;
}

static BOOL __attribute__((unused)) PushCustomSettings(YTSettingsViewController *settingsController, BOOL animated) {
    UINavigationController *navigationController = NavigationControllerForSettingsController(settingsController);
    UIViewController *custom = CreateCustomSettingsDestination(settingsController);
    if (!navigationController || !custom)
        return NO;
    [navigationController pushViewController:custom animated:animated];
    return YES;
}

static BOOL SettingsCandidateInHierarchy(UIViewController *controller, NSUInteger depth) {
    if (!controller || depth > 8)
        return NO;
    if (IsDeArrowSettingsCandidate(controller))
        return YES;
    if (controller.presentedViewController &&
        SettingsCandidateInHierarchy(controller.presentedViewController, depth + 1))
        return YES;
    if ([controller isKindOfClass:[UINavigationController class]]) {
        for (UIViewController *child in ((UINavigationController *)controller).viewControllers) {
            if (SettingsCandidateInHierarchy(child, depth + 1))
                return YES;
        }
    }
    if ([controller isKindOfClass:[UISplitViewController class]]) {
        for (UIViewController *child in ((UISplitViewController *)controller).viewControllers) {
            if (SettingsCandidateInHierarchy(child, depth + 1))
                return YES;
        }
    }
    for (UIViewController *child in controller.childViewControllers) {
        if (SettingsCandidateInHierarchy(child, depth + 1))
            return YES;
    }
    return NO;
}

static UIViewController *CreateCustomSettingsSplitDestination(YTSettingsViewController *settingsController) {
    UIViewController *custom = CreateCustomSettingsDestination(settingsController);
    if (!custom)
        return nil;
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:custom];
    navigationController.navigationBarHidden = NO;
    YTSettingsSectionItemManager *manager = SettingsManagerForController(settingsController);
    if (manager) {
        objc_setAssociatedObject(custom, SettingsControllerManagerKey, manager, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(navigationController, SettingsControllerManagerKey, manager, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return navigationController;
}

static void InstallSplitViewSettingsHook(Class targetClass) {
    BOOL installed = DeArrowInstallInstanceHook(targetClass, @selector(setSecondViewController:), ^id(IMP original, SEL selector) {
        return ^(id object, SEL command, UIViewController *viewController) {
            YTSettingsViewController *settingsController = SettingsControllerInViewController(SettingsObjectValue(object, @"viewController"), 0);
            if (!settingsController)
                settingsController = SettingsControllerInViewController(object, 0);
            UIViewController *replacement = nil;
            if (settingsController && IsDeArrowSettingsDestination(viewController))
                replacement = CreateCustomSettingsSplitDestination(settingsController);
            ((void (*)(id, SEL, UIViewController *))original)(object, command, replacement ?: viewController);
        };
    });
    (void)installed;
}

static BOOL ReplaceLoadedSettingsDestination(YTSettingsViewController *settingsController) {
    if (!settingsController)
        return NO;
    NSString *title = settingsController.title ?: settingsController.navigationItem.title;
    UINavigationController *navigationController = settingsController.navigationController;
    NSUInteger destinationIndex = navigationController
        ? [navigationController.viewControllers indexOfObjectIdenticalTo:settingsController]
        : NSNotFound;
    if (![title isEqualToString:@"DeArrow"])
        return NO;
    if (!navigationController)
        return NO;
    if (destinationIndex == NSNotFound)
        return NO;
    YTSettingsViewController *sourceController = nil;
    for (UIViewController *candidate in navigationController.viewControllers) {
        if (candidate == settingsController)
            continue;
        sourceController = SettingsControllerFromObject(candidate);
        if (sourceController)
            break;
    }
    UIViewController *custom = CreateCustomSettingsDestination(sourceController ?: settingsController);
    if (!custom)
        return NO;
    NSMutableArray *viewControllers = [navigationController.viewControllers mutableCopy];
    viewControllers[destinationIndex] = custom;
    [navigationController setViewControllers:viewControllers animated:NO];
    return YES;
}

static BOOL ReplaceNestedSettingsDestination(YTSettingsViewController *settingsController) {
    if (!settingsController)
        return NO;
    UIViewController *parent = settingsController.parentViewController;
    if (![NSStringFromClass([parent class]) isEqualToString:@"YTHeaderContentComboViewController"])
        return NO;
    YTSettingsViewController *sourceController = nil;
    UINavigationController *navigationController = settingsController.navigationController;
    for (UIViewController *candidate in navigationController.viewControllers) {
        if (candidate == parent)
            continue;
        sourceController = SettingsControllerInViewController(candidate, 0);
        if (sourceController)
            break;
    }
    UIViewController *custom = CreateCustomSettingsDestination(sourceController ?: settingsController);
    if (!custom)
        return NO;
    [settingsController willMoveToParentViewController:nil];
    [settingsController.view removeFromSuperview];
    [settingsController removeFromParentViewController];
    [parent addChildViewController:custom];
    UIView *container = parent.view;
    custom.view.frame = container.bounds;
    custom.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [container addSubview:custom.view];
    [container bringSubviewToFront:custom.view];
    [custom didMoveToParentViewController:parent];
    parent.title = custom.title;
    parent.navigationItem.title = custom.title;
    objc_setAssociatedObject(parent, NestedCustomSettingsKey, custom, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    void (^layoutCustom)(UIViewController *) = ^(UIViewController *containerController) {
        UIViewController *nestedCustom = objc_getAssociatedObject(containerController, NestedCustomSettingsKey);
        UIView *containerView = containerController.view;
        if (!nestedCustom || !containerView)
            return;
        if (nestedCustom.view.superview != containerView) {
            [nestedCustom.view removeFromSuperview];
            [containerView addSubview:nestedCustom.view];
        }
        nestedCustom.view.hidden = NO;
        nestedCustom.view.alpha = 1.0;
        nestedCustom.view.frame = containerView.bounds;
        nestedCustom.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [containerView bringSubviewToFront:nestedCustom.view];
        [nestedCustom.view setNeedsLayout];
    };
    DeArrowInstallInstanceHook([parent class], @selector(viewDidLayoutSubviews), ^id(IMP original, SEL selector) {
        return ^(id object, SEL command) {
            ((void (*)(id, SEL))original)(object, command);
            layoutCustom(object);
        };
    });
    DeArrowInstallInstanceHook([parent class], @selector(viewWillAppear:), ^id(IMP original, SEL selector) {
        return ^(id object, SEL command, BOOL animated) {
            ((void (*)(id, SEL, BOOL))original)(object, command, animated);
            layoutCustom(object);
        };
    });
    DeArrowInstallInstanceHook([parent class], @selector(viewDidAppear:), ^id(IMP original, SEL selector) {
        return ^(id object, SEL command, BOOL animated) {
            ((void (*)(id, SEL, BOOL))original)(object, command, animated);
            layoutCustom(object);
        };
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        layoutCustom(parent);
    });
    return YES;
}

void DeArrowInstallSettingsIntegration(void) {
    Class groupClass = NSClassFromString(@"YTSettingsGroupData");
    if (groupClass) {
        DeArrowInstallInstanceHook(groupClass, @selector(orderedCategories), ^id(IMP original, SEL selector) {
            return ^id(id object, SEL command) {
                if ([object respondsToSelector:@selector(type)] && [(YTSettingsGroupData *)object type] == DeArrowSettingsGroup)
                    return @[@(DeArrowSettingsCategory)];
                return ((id (*)(id, SEL))original)(object, command);
            };
        });
        DeArrowInstallInstanceHook(groupClass, @selector(orderedCategoriesForGroupType:), ^id(IMP original, SEL selector) {
            return ^id(id object, SEL command, NSUInteger type) {
                if (type == DeArrowSettingsGroup)
                    return @[@(DeArrowSettingsCategory)];
                return ((id (*)(id, SEL, NSUInteger))original)(object, command, type);
            };
        });
        DeArrowInstallInstanceHook(groupClass, @selector(titleForSettingGroupType:), ^id(IMP original, SEL selector) {
            return ^id(id object, SEL command, NSUInteger type) {
                if (type == DeArrowSettingsGroup)
                    return nil;
                return ((id (*)(id, SEL, NSUInteger))original)(object, command, type);
            };
        });
    }
    Class groupPresentationClass = NSClassFromString(@"YTAppSettingsGroupPresentationData");
    if (groupPresentationClass)
        DeArrowInstallClassHook(groupPresentationClass, @selector(orderedGroups), ^id(IMP original, SEL selector) {
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
    Class splitViewClass = NSClassFromString(@"YTWrapperSplitViewController");
    if (splitViewClass)
        InstallSplitViewSettingsHook(splitViewClass);
    Class settingsClass = SettingsViewControllerClass();
    if (settingsClass)
        DeArrowInstallInstanceHook(settingsClass, @selector(viewDidLoad), ^id(IMP original, SEL selector) {
            return ^(id object, SEL command) {
                ((void (*)(id, SEL))original)(object, command);
                Class splitClass = NSClassFromString(@"YTWrapperSplitViewController");
                if (splitClass)
                    InstallSplitViewSettingsHook(splitClass);
                if (!ReplaceNestedSettingsDestination(object) && !ReplaceLoadedSettingsDestination(object))
                    ConfigureSettingsSectionForController(object);
            };
        });
    if (settingsClass)
        DeArrowInstallInstanceHook(settingsClass, @selector(sendSettingsNavigationEndpointForCategory:), ^id(IMP original, SEL selector) {
            return ^(id object, SEL command, NSUInteger category) {
                if (category == DeArrowSettingsCategory) {
                    if (PushCustomSettings(object, YES))
                        return;
                }
                ((void (*)(id, SEL, NSUInteger))original)(object, command, category);
            };
        });
    if (settingsClass)
        DeArrowInstallInstanceHook(settingsClass, @selector(didReceiveDrillDownItem:), ^id(IMP original, SEL selector) {
            return ^(id object, SEL command, id item) {
                if (SettingsCategoryValue(item, 0).unsignedIntegerValue == DeArrowSettingsCategory) {
                    if (PushCustomSettings(object, YES))
                        return;
                }
                ((void (*)(id, SEL, id))original)(object, command, item);
            };
        });
    Class actionClass = NSClassFromString(@"YTAppSettingsSectionItemActionController");
    if (actionClass)
        DeArrowInstallInstanceHook(actionClass, @selector(displaySettingsViewController:), ^id(IMP original, SEL selector) {
            return ^(id object, SEL command, UIViewController *viewController) {
                if (IsDeArrowSettingsDestination(viewController)) {
                    YTSettingsViewController *settingsController = SettingsControllerInViewController(SettingsObjectValue(object, @"viewController"), 0);
                    if (!settingsController)
                        settingsController = SettingsControllerInViewController(SettingsObjectValue(object, @"settingsViewController"), 0);
                    if (!settingsController)
                        settingsController = SettingsControllerInViewController(object, 0);
                    if (!settingsController) {
                        for (UIWindow *window in [UIApplication sharedApplication].windows) {
                            settingsController = SettingsControllerInViewController(window.rootViewController, 0);
                            if (settingsController)
                                break;
                        }
                    }
                    UIViewController *custom = CreateCustomSettingsDestination(settingsController);
                    if (custom) {
                        ((void (*)(id, SEL, UIViewController *))original)(object, command, custom);
                        return;
                    }
                }
                ((void (*)(id, SEL, UIViewController *))original)(object, command, viewController);
            };
        });
}
