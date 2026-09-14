#import "SettingsIntegration.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "HookSupport.h"
#import "SettingsViewController.h"
#import "YouTube.h"

static const NSUInteger DeArrowSettingsCategory      = 0x64617272;
static const NSUInteger DeArrowSettingsGroup         = 0x64617270;
static const NSInteger  DeArrowSettingsIconType      = 0x64617269;
static void            *SettingsManagerControllerKey = &SettingsManagerControllerKey;
static void            *SettingsControllerManagerKey = &SettingsControllerManagerKey;

static id SettingsIvarObject(id object, const char *name);
static UIViewController *
CreateCustomSettingsDestination(YTSettingsViewController *settingsController);
static void RegisterSettingsCategory(void);

static BOOL SettingsHostAvailable(void)
{
    Class groupClass = NSClassFromString(@"YTSettingsGroupData");
    SEL   selector   = NSSelectorFromString(@"registerSettingsIntegrationCategory:");
    return groupClass && [groupClass respondsToSelector:selector];
}

static id SettingsObjectValue(id object, NSString *key)
{
    if (!object || key.length == 0)
        return nil;
    @try
    {
        id value = [object valueForKey:key];
        if (value)
            return value;
    }
    @catch (__unused NSException *exception)
    {
    }
    return SettingsIvarObject(object, key.UTF8String);
}
static id SettingsIvarObject(id object, const char *name)
{
    if (!object || !name)
        return nil;
    Ivar        ivar     = class_getInstanceVariable(object_getClass(object), name);
    const char *encoding = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if (!encoding || encoding[0] != '@')
        return nil;
    return object_getIvar(object, ivar);
}

static Class SettingsViewControllerClass(void)
{
    return NSClassFromString(@"YTSettingsViewController");
}

static Class SettingsManagerClass(void)
{
    return NSClassFromString(@"YTSettingsSectionItemManager");
}

static void RegisterSettingsCategory(void)
{
    Class groupClass = NSClassFromString(@"YTSettingsGroupData");
    SEL   selector   = NSSelectorFromString(@"registerSettingsIntegrationCategory:");
    if (groupClass && [groupClass respondsToSelector:selector])
    {
        void (*message)(id, SEL, NSInteger) = (void (*)(id, SEL, NSInteger)) objc_msgSend;
        message(groupClass, selector, DeArrowSettingsCategory);
    }
}

static const void *SharedSettingsIconImageKey(void)
{
    return (const void *) sel_registerName("settingsIntegrationIconImage");
}

static void InstallSettingsObservers(void)
{
    static BOOL installed = NO;
    @synchronized([NSNotificationCenter defaultCenter])
    {
        if (installed)
            return;
        [[NSNotificationCenter defaultCenter]
            addObserverForName:@"SettingsIntegrationConfigureCategory"
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *notification) {
                        NSNumber *category = notification.userInfo[@"category"];
                        if (category.unsignedIntegerValue == DeArrowSettingsCategory)
                            DeArrowConfigureSettingsSection(notification.object);
                    }];
        [[NSNotificationCenter defaultCenter]
            addObserverForName:@"SettingsIntegrationCreateSettingsDestination"
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *notification) {
                        NSNumber *category = notification.userInfo[@"category"];
                        if (category.unsignedIntegerValue != DeArrowSettingsCategory)
                            return;
                        YTSettingsViewController *controller = notification.object;
                        UIViewController *destination = CreateCustomSettingsDestination(controller);
                        if (destination)
                            ((NSMutableDictionary *) notification.userInfo)[@"destination"] =
                                destination;
                    }];
        [[NSNotificationCenter defaultCenter]
            addObserverForName:@"SettingsIntegrationHostReady"
                        object:nil
                         queue:nil
                    usingBlock:^(__unused NSNotification *notification) {
                        if (SettingsHostAvailable())
                            RegisterSettingsCategory();
                    }];
        installed = YES;
    }
}

UIImage *SettingsIconImage(void)
{
    static UIImage        *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CGSize size = CGSizeMake(24.0, 24.0);
        UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
        UIBezierPath *background =
            [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.0, 0.0, size.width, size.height)
                                       cornerRadius:5.25];
        [[UIColor colorWithRed:1.0 green:0.0 blue:0.2 alpha:1.0] setFill];
        [background fill];
        [[UIColor whiteColor] setFill];
        UIBezierPath *top = [UIBezierPath bezierPath];
        [top moveToPoint:CGPointMake(5.8, 6.375)];
        [top addLineToPoint:CGPointMake(18.2, 6.375)];
        [top addLineToPoint:CGPointMake(14.25, 12.0)];
        [top addLineToPoint:CGPointMake(9.75, 12.0)];
        [top closePath];
        [top fill];
        UIBezierPath *bottom = [UIBezierPath bezierPath];
        [bottom moveToPoint:CGPointMake(5.8, 17.625)];
        [bottom addLineToPoint:CGPointMake(18.2, 17.625)];
        [bottom addLineToPoint:CGPointMake(14.25, 12.0)];
        [bottom addLineToPoint:CGPointMake(9.75, 12.0)];
        [bottom closePath];
        [bottom fill];
        [[UIColor colorWithRed:1.0 green:0.0 blue:0.2 alpha:1.0] setFill];
        [[UIBezierPath bezierPathWithArcCenter:CGPointMake(12.1875, 12.0)
                                        radius:2.25
                                    startAngle:0.0
                                      endAngle:2.0 * M_PI
                                     clockwise:YES] fill];
        image = [UIGraphicsGetImageFromCurrentImageContext()
            imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        UIGraphicsEndImageContext();
    });
    return image;
}

static YTIIcon *SettingsIcon(void)
{
    YTIIcon *icon = [NSClassFromString(@"YTIIcon") new];
    if (!icon)
        return nil;
    if ([icon respondsToSelector:@selector(setIconType:)])
        icon.iconType = DeArrowSettingsIconType;
    UIImage *image = SettingsIconImage();
    if (image)
        objc_setAssociatedObject(icon, SharedSettingsIconImageKey(), image,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return icon;
}

static YTSettingsViewController *SettingsControllerFromObject(id object)
{
    Class settingsClass = SettingsViewControllerClass();
    if (settingsClass && [object isKindOfClass:settingsClass])
        return object;
    return nil;
}

static YTSettingsViewController *SettingsControllerInViewController(UIViewController *controller,
                                                                    NSUInteger        depth)
{
    if (!controller || depth > 12)
        return nil;
    YTSettingsViewController *settingsController = SettingsControllerFromObject(controller);
    if (settingsController)
        return settingsController;
    if (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed)
    {
        settingsController =
            SettingsControllerInViewController(controller.presentedViewController, depth + 1);
        if (settingsController)
            return settingsController;
    }
    if ([controller isKindOfClass:[UINavigationController class]])
    {
        for (UIViewController *child in ((UINavigationController *) controller).viewControllers)
        {
            settingsController = SettingsControllerInViewController(child, depth + 1);
            if (settingsController)
                return settingsController;
        }
    }
    if ([controller isKindOfClass:[UISplitViewController class]])
    {
        for (UIViewController *child in ((UISplitViewController *) controller).viewControllers)
        {
            settingsController = SettingsControllerInViewController(child, depth + 1);
            if (settingsController)
                return settingsController;
        }
    }
    for (UIViewController *child in controller.childViewControllers)
    {
        settingsController = SettingsControllerInViewController(child, depth + 1);
        if (settingsController)
            return settingsController;
    }
    return nil;
}

static YTSettingsSectionItemManager *
SettingsManagerForController(YTSettingsViewController *controller)
{
    if (!controller)
        return nil;
    YTSettingsSectionItemManager *manager =
        objc_getAssociatedObject(controller, SettingsControllerManagerKey);
    if (!manager)
        manager =
            objc_getAssociatedObject(controller.navigationController, SettingsControllerManagerKey);
    if (!manager)
    {
        Class managerClass = SettingsManagerClass();
        for (NSString *key in @[ @"_sectionItemManager", @"sectionItemManager" ])
        {
            id candidate = SettingsObjectValue(controller, key)
                               ?: SettingsIvarObject(controller, key.UTF8String);
            if (candidate && (!managerClass || [candidate isKindOfClass:managerClass]))
            {
                manager = candidate;
                if (manager)
                    break;
            }
        }
    }
    if (manager)
    {
        objc_setAssociatedObject(controller, SettingsControllerManagerKey, manager,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(manager, SettingsManagerControllerKey, controller,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return manager;
}

static YTSettingsViewController *SettingsControllerForManager(YTSettingsSectionItemManager *manager)
{
    if (!manager)
        return nil;
    YTSettingsViewController *controller =
        objc_getAssociatedObject(manager, SettingsManagerControllerKey);
    if (controller)
        return controller;
    for (NSString *key in
         @[ @"_dataDelegate", @"_settingsViewControllerDelegate", @"parentResponder" ])
    {
        id candidate = SettingsObjectValue(manager, key);
        controller   = SettingsControllerFromObject(candidate);
        if (controller)
            return controller;
        id responder = candidate;
        for (NSUInteger depth = 0; responder && depth < 8; depth++)
        {
            controller = SettingsControllerFromObject(responder);
            if (controller)
                return controller;
            if (![responder respondsToSelector:@selector(nextResponder)])
                break;
            responder = [responder nextResponder];
        }
    }
    for (UIWindow *window in [UIApplication sharedApplication].windows)
    {
        controller = SettingsControllerInViewController(window.rootViewController, 0);
        if (controller)
            return controller;
    }
    return nil;
}

static NSNumber *SettingsCategoryValue(id object, NSUInteger depth)
{
    if (!object || depth > 4)
        return nil;
    for (NSString *key in @[ @"category", @"categoryID", @"categoryId", @"settingsCategory" ])
    {
        id value = SettingsObjectValue(object, key);
        if ([value respondsToSelector:@selector(unsignedIntegerValue)])
            return @([value unsignedIntegerValue]);
    }
    for (NSString *key in @[ @"model", @"content", @"navigationEndpoint", @"endpoint" ])
    {
        NSNumber *value = SettingsCategoryValue(SettingsObjectValue(object, key), depth + 1);
        if (value)
            return value;
    }
    NSString *description = [object description] ?: @"";
    NSRange   marker      = [description rangeOfString:@"category_id:"];
    if (marker.location == NSNotFound)
        return nil;
    NSString          *suffix   = [description substringFromIndex:NSMaxRange(marker)];
    NSScanner         *scanner  = [NSScanner scannerWithString:suffix];
    unsigned long long category = 0;
    return [scanner scanUnsignedLongLong:&category] ? @(category) : nil;
}

static BOOL IsDeArrowSettingsCandidate(UIViewController *candidate)
{
    if (!candidate)
        return NO;
    NSNumber *category = SettingsCategoryValue(candidate, 0);
    if (!category)
        category = SettingsCategoryValue(SettingsObjectValue(candidate, @"content"), 0);
    return category.unsignedIntegerValue == DeArrowSettingsCategory;
}

static UINavigationController *
SettingsNavigationControllerForController(YTSettingsViewController *controller)
{
    if (!controller)
        return nil;
    if (controller.navigationController)
        return controller.navigationController;
    for (UIWindow *window in [UIApplication sharedApplication].windows)
    {
        UIViewController *root = window.rootViewController;
        for (NSUInteger depth = 0; root && depth < 12; depth++)
        {
            if ([root isKindOfClass:[UINavigationController class]])
            {
                UINavigationController *navigationController = (UINavigationController *) root;
                if ([navigationController.viewControllers containsObject:controller])
                    return navigationController;
                root = navigationController.visibleViewController;
            }
            else if (root.presentedViewController && !root.presentedViewController.isBeingDismissed)
            {
                root = root.presentedViewController;
            }
            else
            {
                UIViewController *next = nil;
                for (UIViewController *child in root.childViewControllers.reverseObjectEnumerator)
                {
                    if (child.viewIfLoaded.window)
                    {
                        next = child;
                        break;
                    }
                }
                root = next;
            }
        }
    }
    return nil;
}

static BOOL PushStandaloneSettings(YTSettingsViewController *controller, BOOL animated)
{
    if (SettingsHostAvailable())
        return NO;
    UINavigationController *navigationController =
        SettingsNavigationControllerForController(controller);
    UIViewController *destination = CreateCustomSettingsDestination(controller);
    if (!navigationController || !destination)
        return NO;
    [navigationController pushViewController:destination animated:animated];
    return YES;
}

static UIViewController *StandaloneDestinationForCandidate(YTSettingsViewController *controller,
                                                           UIViewController         *candidate)
{
    if (SettingsHostAvailable() || !IsDeArrowSettingsCandidate(candidate))
        return nil;
    return CreateCustomSettingsDestination(controller);
}

void DeArrowConfigureSettingsSectionForController(YTSettingsViewController *controller)
{
    if (!controller)
        return;
    YTSettingsSectionItemManager *manager = SettingsManagerForController(controller);
    if (manager)
    {
        objc_setAssociatedObject(controller, SettingsControllerManagerKey, manager,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(manager, SettingsManagerControllerKey, controller,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSMutableArray *items = [NSMutableArray array];
    YTIIcon        *icon  = SettingsIcon();
    SEL             modernSelector =
        @selector(setSectionItems:forCategory:title:icon:titleDescription:headerHidden:);
    if ([controller respondsToSelector:modernSelector])
    {
        void (*message)(id, SEL, NSMutableArray *, NSInteger, NSString *, YTIIcon *, NSString *,
                        BOOL) = (void (*)(id, SEL, NSMutableArray *, NSInteger, NSString *,
                                          YTIIcon *, NSString *, BOOL)) objc_msgSend;
        message(controller, modernSelector, items, DeArrowSettingsCategory, @"DeArrow", icon, nil,
                NO);
        return;
    }
    SEL legacySelector =
        @selector(setSectionItems:forCategory:title:titleDescription:headerHidden:);
    if ([controller respondsToSelector:legacySelector])
    {
        void (*message)(id, SEL, NSMutableArray *, NSInteger, NSString *, NSString *, BOOL) =
            (void (*)(id, SEL, NSMutableArray *, NSInteger, NSString *, NSString *,
                      BOOL)) objc_msgSend;
        message(controller, legacySelector, items, DeArrowSettingsCategory, @"DeArrow", nil, NO);
    }
}

void DeArrowConfigureSettingsSection(YTSettingsSectionItemManager *manager)
{
    YTSettingsViewController *controller = SettingsControllerForManager(manager);
    if (controller)
        DeArrowConfigureSettingsSectionForController(controller);
}

static UIViewController *
CreateCustomSettingsDestination(YTSettingsViewController *settingsController)
{
    UIViewController             *custom  = CreateDeArrowSettingsViewController();
    YTSettingsSectionItemManager *manager = SettingsManagerForController(settingsController);
    if (manager)
        objc_setAssociatedObject(custom, SettingsControllerManagerKey, manager,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return custom;
}

static void InstallStandaloneSettingsHooks(void)
{
    Class groupClass = NSClassFromString(@"YTSettingsGroupData");
    if (groupClass)
    {
        DeArrowInstallInstanceHook(
            groupClass, @selector(orderedCategories), ^id(IMP original, SEL command) {
                return ^id(id object, SEL selector) {
                    if (!SettingsHostAvailable() && [object respondsToSelector:@selector(type)] &&
                        [(YTSettingsGroupData *) object type] == DeArrowSettingsGroup)
                        return @[ @(DeArrowSettingsCategory) ];
                    return ((id (*)(id, SEL)) original)(object, selector);
                };
            });
        DeArrowInstallInstanceHook(
            groupClass, @selector(orderedCategoriesForGroupType:), ^id(IMP original, SEL command) {
                return ^id(id object, SEL selector, NSUInteger type) {
                    if (!SettingsHostAvailable() && type == DeArrowSettingsGroup)
                        return @[ @(DeArrowSettingsCategory) ];
                    return ((id (*)(id, SEL, NSUInteger)) original)(object, selector, type);
                };
            });
        DeArrowInstallInstanceHook(
            groupClass, @selector(titleForSettingGroupType:), ^id(IMP original, SEL command) {
                return ^id(id object, SEL selector, NSUInteger type) {
                    if (!SettingsHostAvailable() && type == DeArrowSettingsGroup)
                        return nil;
                    return ((id (*)(id, SEL, NSUInteger)) original)(object, selector, type);
                };
            });
    }

    Class presentationClass = NSClassFromString(@"YTAppSettingsGroupPresentationData");
    if (presentationClass)
    {
        DeArrowInstallClassHook(
            presentationClass, @selector(orderedGroups), ^id(IMP original, SEL command) {
                return ^id(id object, SEL selector) {
                    NSArray *groups = ((id (*)(id, SEL)) original)(object, selector);
                    if (SettingsHostAvailable())
                        return groups;
                    for (YTSettingsGroupData *group in groups)
                    {
                        if (group.type == DeArrowSettingsGroup)
                            return groups;
                    }
                    Class settingsGroupClass = NSClassFromString(@"YTSettingsGroupData");
                    if (!settingsGroupClass)
                        return groups;
                    NSMutableArray *result = groups.mutableCopy ?: [NSMutableArray array];
                    [result insertObject:[[settingsGroupClass alloc]
                                             initWithGroupType:DeArrowSettingsGroup]
                                 atIndex:0];
                    return result.copy;
                };
            });
    }

    Class managerClass = SettingsManagerClass();
    if (managerClass)
    {
        SEL selector = @selector(initWithParentResponder:controllerDelegate:dataDelegate:
                                 settingsViewControllerDelegate:);
        DeArrowInstallInstanceHook(managerClass, selector, ^id(IMP original, SEL command) {
            return ^id(id object, SEL selector, id parentResponder, id controllerDelegate,
                       id dataDelegate, id settingsViewControllerDelegate) {
                id result = ((id (*)(id, SEL, id, id, id, id)) original)(
                    object, selector, parentResponder, controllerDelegate, dataDelegate,
                    settingsViewControllerDelegate);
                YTSettingsViewController *controller = SettingsControllerFromObject(dataDelegate);
                if (!controller)
                    controller = SettingsControllerFromObject(settingsViewControllerDelegate);
                if (!controller)
                    controller = SettingsControllerFromObject(parentResponder);
                if (result && controller)
                {
                    objc_setAssociatedObject(controller, SettingsControllerManagerKey, result,
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(result, SettingsManagerControllerKey, controller,
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                return result;
            };
        });
        DeArrowInstallInstanceHook(
            managerClass, @selector(updateSectionForCategory:withEntry:),
            ^id(IMP original, SEL command) {
                return ^(id object, SEL selector, NSUInteger category, id entry) {
                    if (!SettingsHostAvailable() && category == DeArrowSettingsCategory)
                    {
                        DeArrowConfigureSettingsSection((YTSettingsSectionItemManager *) object);
                        return;
                    }
                    ((void (*)(id, SEL, NSUInteger, id)) original)(object, selector, category,
                                                                   entry);
                };
            });
    }

    Class settingsClass = SettingsViewControllerClass();
    if (settingsClass)
    {
        DeArrowInstallInstanceHook(settingsClass, @selector(viewDidLoad),
                                   ^id(IMP original, SEL command) {
                                       return ^(id object, SEL selector) {
                                           ((void (*)(id, SEL)) original)(object, selector);
                                           if (!SettingsHostAvailable())
                                               DeArrowConfigureSettingsSectionForController(
                                                   (YTSettingsViewController *) object);
                                       };
                                   });
        DeArrowInstallInstanceHook(
            settingsClass, @selector(sendSettingsNavigationEndpointForCategory:),
            ^id(IMP original, SEL command) {
                return ^(id object, SEL selector, NSUInteger category) {
                    if (!SettingsHostAvailable() && category == DeArrowSettingsCategory &&
                        PushStandaloneSettings((YTSettingsViewController *) object, YES))
                        return;
                    ((void (*)(id, SEL, NSUInteger)) original)(object, selector, category);
                };
            });
        DeArrowInstallInstanceHook(
            settingsClass, @selector(didReceiveDrillDownItem:), ^id(IMP original, SEL command) {
                return ^(id object, SEL selector, id item) {
                    NSNumber *category = SettingsCategoryValue(item, 0);
                    if (!SettingsHostAvailable() &&
                        category.unsignedIntegerValue == DeArrowSettingsCategory &&
                        PushStandaloneSettings((YTSettingsViewController *) object, YES))
                        return;
                    ((void (*)(id, SEL, id)) original)(object, selector, item);
                };
            });
        for (NSString *selectorName in @[
                 @"pushViewController:", @"pushViewController:animated:",
                 @"showOrPushViewController:", @"showViewController:sender:"
             ])
        {
            SEL selector = NSSelectorFromString(selectorName);
            DeArrowInstallInstanceHook(settingsClass, selector, ^id(IMP original, SEL command) {
                if (sel_isEqual(command, @selector(pushViewController:animated:)))
                {
                    return ^(id object, SEL selector, UIViewController *candidate, BOOL animated) {
                        UIViewController *replacement = StandaloneDestinationForCandidate(
                            (YTSettingsViewController *) object, candidate);
                        if (replacement)
                        {
                            [((YTSettingsViewController *) object).navigationController
                                pushViewController:replacement
                                          animated:animated];
                            return;
                        }
                        ((void (*)(id, SEL, UIViewController *, BOOL)) original)(
                            object, selector, candidate, animated);
                    };
                }
                if (sel_isEqual(command, @selector(showViewController:sender:)))
                {
                    return ^(id object, SEL selector, UIViewController *candidate, id sender) {
                        UIViewController *replacement = StandaloneDestinationForCandidate(
                            (YTSettingsViewController *) object, candidate);
                        if (replacement)
                        {
                            [((YTSettingsViewController *) object).navigationController
                                pushViewController:replacement
                                          animated:YES];
                            return;
                        }
                        ((void (*)(id, SEL, UIViewController *, id)) original)(object, selector,
                                                                               candidate, sender);
                    };
                }
                return ^(id object, SEL selector, UIViewController *candidate) {
                    UIViewController *replacement = StandaloneDestinationForCandidate(
                        (YTSettingsViewController *) object, candidate);
                    if (replacement)
                    {
                        [((YTSettingsViewController *) object).navigationController
                            pushViewController:replacement
                                      animated:YES];
                        return;
                    }
                    ((void (*)(id, SEL, UIViewController *)) original)(object, selector, candidate);
                };
            });
        }
    }

    Class splitClass = NSClassFromString(@"YTWrapperSplitViewController");
    if (splitClass)
    {
        DeArrowInstallInstanceHook(
            splitClass, @selector(setSecondViewController:), ^id(IMP original, SEL command) {
                return ^(id object, SEL selector, UIViewController *candidate) {
                    YTSettingsViewController *controller = SettingsControllerInViewController(
                        SettingsObjectValue(object, @"viewController"), 0);
                    UIViewController *replacement =
                        StandaloneDestinationForCandidate(controller, candidate);
                    if (replacement)
                    {
                        UINavigationController *navigationController =
                            [[UINavigationController alloc] initWithRootViewController:replacement];
                        ((void (*)(id, SEL, UIViewController *)) original)(object, selector,
                                                                           navigationController);
                        return;
                    }
                    ((void (*)(id, SEL, UIViewController *)) original)(object, selector, candidate);
                };
            });
    }

    Class actionClass = NSClassFromString(@"YTAppSettingsSectionItemActionController");
    if (actionClass)
    {
        DeArrowInstallInstanceHook(
            actionClass, @selector(displaySettingsViewController:), ^id(IMP original, SEL command) {
                return ^(id object, SEL selector, UIViewController *candidate) {
                    if (!SettingsHostAvailable() && IsDeArrowSettingsCandidate(candidate))
                    {
                        YTSettingsViewController *controller = SettingsControllerInViewController(
                            SettingsObjectValue(object, @"viewController"), 0);
                        UIViewController *replacement = CreateCustomSettingsDestination(controller);
                        if (replacement)
                        {
                            ((void (*)(id, SEL, UIViewController *)) original)(object, selector,
                                                                               replacement);
                            return;
                        }
                    }
                    ((void (*)(id, SEL, UIViewController *)) original)(object, selector, candidate);
                };
            });
    }
}

void DeArrowInstallSettingsIntegration(void)
{
    InstallSettingsObservers();
    if (SettingsHostAvailable())
        RegisterSettingsCategory();
    else
        InstallStandaloneSettingsHooks();
}
