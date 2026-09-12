#import "SettingsIntegration.h"

#import <objc/message.h>
#import <objc/runtime.h>

#import "SettingsViewController.h"
#import "YouTube.h"

static const NSInteger DeArrowSettingsCategory = 0x64617272;
static const NSInteger DeArrowSettingsGroup = 0x64617270;
static void *SettingsManagerControllerKey = &SettingsManagerControllerKey;
static void *SettingsNavigationTokenKey = &SettingsNavigationTokenKey;

static id ExplicitValue(id object, NSString *key) {
    if (!object || key.length == 0)
        return nil;
    SEL selector = NSSelectorFromString(key);
    if (![object respondsToSelector:selector])
        return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static YTSettingsViewController *SettingsControllerFromObject(id object) {
    Class settingsClass = NSClassFromString(@"YTSettingsViewController");
    if (settingsClass && [object isKindOfClass:settingsClass])
        return object;
    return nil;
}

static YTSettingsViewController *SettingsControllerForManager(YTSettingsSectionItemManager *manager) {
    YTSettingsViewController *controller = objc_getAssociatedObject(manager, SettingsManagerControllerKey);
    if (controller)
        return controller;
    for (NSString *key in @[@"_dataDelegate", @"_settingsViewControllerDelegate", @"parentResponder"]) {
        id candidate = ExplicitValue(manager, key);
        controller = SettingsControllerFromObject(candidate);
        if (controller) {
            objc_setAssociatedObject(manager, SettingsManagerControllerKey, controller, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return controller;
        }
    }
    return nil;
}

static UINavigationController *NavigationControllerForController(UIViewController *controller) {
    if (!controller)
        return nil;
    if ([controller isKindOfClass:[UINavigationController class]])
        return (UINavigationController *)controller;
    return controller.navigationController;
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

static BOOL PushCustomSettings(YTSettingsViewController *controller, BOOL animated) {
    UINavigationController *navigationController = NavigationControllerForController(controller);
    if (!navigationController)
        return NO;
    UIViewController *custom = CreateDeArrowSettingsViewController();
    if (!custom)
        return NO;
    [navigationController pushViewController:custom animated:animated];
    return YES;
}

static NSNumber *CategoryFromObjectAtDepth(id object, NSUInteger depth) {
    if (!object)
        return nil;
    for (NSString *key in @[@"category", @"categoryID", @"categoryId", @"settingsCategory"]) {
        id value = ExplicitValue(object, key);
        if ([value respondsToSelector:@selector(integerValue)])
            return @([value integerValue]);
    }
    if (depth >= 3)
        return nil;
    for (NSString *key in @[@"model", @"navigationEndpoint", @"endpoint", @"content"]) {
        NSNumber *value = CategoryFromObjectAtDepth(ExplicitValue(object, key), depth + 1);
        if (value)
            return value;
    }
    return nil;
}

static NSNumber *CategoryFromObject(id object) {
    return CategoryFromObjectAtDepth(object, 0);
}

static YTSettingsSectionItem *MakeSectionItem(YTSettingsViewController *controller) {
    Class itemClass = NSClassFromString(@"YTSettingsSectionItem");
    if (!itemClass)
        return nil;
    __weak YTSettingsViewController *weakController = controller;
    BOOL (^selectBlock)(YTSettingsCell *, NSUInteger) = ^BOOL(__unused YTSettingsCell *cell, __unused NSUInteger index) {
        YTSettingsViewController *strongController = weakController;
        if (!strongController)
            return NO;
        return PushCustomSettings(strongController, YES);
    };
    SEL modernSelector = @selector(itemWithTitle:titleDescription:accessibilityIdentifier:detailTextBlock:selectBlock:settingItemId:);
    if ([itemClass respondsToSelector:modernSelector]) {
        id (*message)(id, SEL, NSString *, NSString *, NSString *, id, id, NSUInteger) = (id (*)(id, SEL, NSString *, NSString *, NSString *, id, id, NSUInteger))objc_msgSend;
        return message(itemClass, modernSelector, @"DeArrow", nil, @"dev.adrian.dearrow.settings", nil, selectBlock, (NSUInteger)DeArrowSettingsCategory);
    }
    SEL legacySelector = @selector(itemWithTitle:titleDescription:accessibilityIdentifier:detailTextBlock:selectBlock:);
    if ([itemClass respondsToSelector:legacySelector]) {
        id (*message)(id, SEL, NSString *, NSString *, NSString *, id, id) = (id (*)(id, SEL, NSString *, NSString *, NSString *, id, id))objc_msgSend;
        return message(itemClass, legacySelector, @"DeArrow", nil, @"dev.adrian.dearrow.settings", nil, selectBlock);
    }
    return nil;
}

static void ConfigureSettingsSection(YTSettingsSectionItemManager *manager) {
    YTSettingsViewController *controller = SettingsControllerForManager(manager);
    if (!controller)
        return;
    YTSettingsSectionItem *item = MakeSectionItem(controller);
    if (!item)
        return;
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

void DeArrowInstallSettingsIntegration(void) {
    Class groupPresentationClass = NSClassFromString(@"YTAppSettingsGroupPresentationData");
    Class groupClass = NSClassFromString(@"YTSettingsGroupData");
    if (groupClass) {
        InstallTweakCategoryHook(groupClass);
        InstallInstanceHook(groupClass, @selector(orderedCategories), ^id(IMP original, SEL selector) {
            return ^id(id object, SEL command) {
                if (((YTSettingsGroupData *)object).type == DeArrowSettingsGroup)
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
    if (groupPresentationClass) {
        InstallClassHook(groupPresentationClass, @selector(orderedGroups), ^id(IMP original, SEL selector) {
            return ^id(id object, SEL command) {
                NSArray *groups = ((id (*)(id, SEL))original)(object, command);
                Class settingsGroupClass = NSClassFromString(@"YTSettingsGroupData");
                if (!settingsGroupClass)
                    return groups;
                if ([settingsGroupClass respondsToSelector:@selector(tweaks)]) {
                    NSArray *categories = [settingsGroupClass tweaks];
                    if ([categories containsObject:@(DeArrowSettingsCategory)])
                        return groups;
                }
                for (YTSettingsGroupData *group in groups) {
                    if (group.type == DeArrowSettingsGroup)
                        return groups;
                }
                NSMutableArray *result = [groups mutableCopy] ?: [NSMutableArray array];
                [result insertObject:[[settingsGroupClass alloc] initWithGroupType:DeArrowSettingsGroup] atIndex:0];
                return result.copy;
            };
        });
    }
    Class managerClass = NSClassFromString(@"YTSettingsSectionItemManager");
    if (managerClass) {
        InstallInstanceHook(managerClass, @selector(initWithParentResponder:controllerDelegate:dataDelegate:settingsViewControllerDelegate:), ^id(IMP original, SEL selector) {
            return ^id(id object, SEL command, id parentResponder, id controllerDelegate, id dataDelegate, id settingsViewControllerDelegate) {
                id result = ((id (*)(id, SEL, id, id, id, id))original)(object, command, parentResponder, controllerDelegate, dataDelegate, settingsViewControllerDelegate);
                YTSettingsViewController *controller = SettingsControllerFromObject(dataDelegate) ?: SettingsControllerFromObject(settingsViewControllerDelegate) ?: SettingsControllerFromObject(parentResponder);
                if (result && controller)
                    objc_setAssociatedObject(result, SettingsManagerControllerKey, controller, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
    Class settingsClass = NSClassFromString(@"YTSettingsViewController");
    if (!settingsClass)
        return;
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
            if ([CategoryFromObject(item) integerValue] == DeArrowSettingsCategory) {
                if (!PushCustomSettings(object, YES))
                    ArmNavigationToken(object);
                return;
            }
            ((void (*)(id, SEL, id))original)(object, command, item);
        };
    });
    InstallInstanceHook(settingsClass, @selector(pushViewController:), ^id(IMP original, SEL selector) {
        return ^(id object, SEL command, UIViewController *viewController) {
            if (ConsumeNavigationToken(object)) {
                UIViewController *custom = CreateDeArrowSettingsViewController();
                if (custom) {
                    [((UIViewController *)object).navigationController pushViewController:custom animated:YES];
                    return;
                }
            }
            ((void (*)(id, SEL, UIViewController *))original)(object, command, viewController);
        };
    });
    InstallInstanceHook(settingsClass, @selector(pushViewController:animated:), ^id(IMP original, SEL selector) {
        return ^(id object, SEL command, UIViewController *viewController, BOOL animated) {
            if (ConsumeNavigationToken(object)) {
                UIViewController *custom = CreateDeArrowSettingsViewController();
                if (custom) {
                    [((UIViewController *)object).navigationController pushViewController:custom animated:animated];
                    return;
                }
            }
            ((void (*)(id, SEL, UIViewController *, BOOL))original)(object, command, viewController, animated);
        };
    });
    InstallInstanceHook(settingsClass, @selector(showOrPushViewController:), ^id(IMP original, SEL selector) {
        return ^(id object, SEL command, UIViewController *viewController) {
            if (ConsumeNavigationToken(object)) {
                UIViewController *custom = CreateDeArrowSettingsViewController();
                if (custom) {
                    [((UIViewController *)object).navigationController pushViewController:custom animated:YES];
                    return;
                }
            }
            ((void (*)(id, SEL, UIViewController *))original)(object, command, viewController);
        };
    });
    InstallInstanceHook(settingsClass, @selector(showViewController:sender:), ^id(IMP original, SEL selector) {
        return ^(id object, SEL command, UIViewController *viewController, id sender) {
            if (ConsumeNavigationToken(object)) {
                UIViewController *custom = CreateDeArrowSettingsViewController();
                if (custom) {
                    [((UIViewController *)object).navigationController pushViewController:custom animated:YES];
                    return;
                }
            }
            ((void (*)(id, SEL, UIViewController *, id))original)(object, command, viewController, sender);
        };
    });
}
