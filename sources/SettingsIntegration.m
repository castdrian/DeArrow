#import "SettingsIntegration.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "HookSupport.h"
#import "SettingsViewController.h"
#import "YouTube.h"

static const NSUInteger DeArrowSettingsCategory      = 0x64617272;
static const NSInteger  DeArrowSettingsIconType      = 461;
static void            *SettingsManagerControllerKey = &SettingsManagerControllerKey;
static void            *SettingsControllerManagerKey = &SettingsControllerManagerKey;

static id SettingsIvarObject(id object, const char *name);
static UIViewController *
CreateCustomSettingsDestination(YTSettingsViewController *settingsController);
static void RegisterSettingsCategory(void);

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

static BOOL SettingsHostAvailable(void)
{
    Class groupClass = NSClassFromString(@"YTSettingsGroupData");
    SEL   selector   = NSSelectorFromString(@"registerSettingsIntegrationCategory:");
    return groupClass && [groupClass respondsToSelector:selector];
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
        [[UIBezierPath bezierPathWithArcCenter:CGPointMake(12.1875, 12.0)
                                        radius:2.25
                                    startAngle:0.0
                                      endAngle:2.0 * M_PI
                                     clockwise:YES] fill];
        image = [UIGraphicsGetImageFromCurrentImageContext()
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
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

void DeArrowInstallSettingsIntegration(void)
{
    InstallSettingsObservers();
    dispatch_async(dispatch_get_main_queue(), ^{
        if (SettingsHostAvailable())
            RegisterSettingsCategory();
        else
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                               if (SettingsHostAvailable())
                                   RegisterSettingsCategory();
                           });
    });
}
