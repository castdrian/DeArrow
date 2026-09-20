#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "SettingsIntegration.h"
#import "SettingsViewController.h"
#import "YouTube.h"

static const NSUInteger SettingsGroup    = 0x64617270;
static const NSUInteger SettingsCategory = 0x64617272;
static BOOL SettingsHostWasAnnounced    = NO;
static void *SettingsManagerKey         = &SettingsManagerKey;
static void *SettingsControllerKey      = &SettingsControllerKey;

static BOOL SettingsHostAvailable(void)
{
    Class groupClass = NSClassFromString(@"YTSettingsGroupData");
    SEL selector     = NSSelectorFromString(@"registerSettingsIntegrationCategory:");
    return groupClass && [groupClass respondsToSelector:selector];
}

static id SettingsIvarValue(id object, const char *name)
{
    if (!object || !name)
        return nil;
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    if (!ivar || ivar_getTypeEncoding(ivar)[0] != '@')
        return nil;
    return object_getIvar(object, ivar);
}

static id SettingsValue(id object, NSString *key)
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
    return SettingsIvarValue(object, key.UTF8String);
}

static YTSettingsViewController *SettingsController(id object)
{
    Class controllerClass = NSClassFromString(@"YTSettingsViewController");
    return controllerClass && [object isKindOfClass:controllerClass] ? object : nil;
}

static YTSettingsViewController *SettingsControllerInViewController(UIViewController *controller,
                                                                     NSUInteger depth)
{
    if (!controller || depth > 10)
        return nil;
    YTSettingsViewController *settingsController = SettingsController(controller);
    if (settingsController)
        return settingsController;
    if (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed)
    {
        settingsController = SettingsControllerInViewController(
            controller.presentedViewController, depth + 1);
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

static UINavigationController *SettingsNavigationControllerContaining(
    UIViewController *controller, UIViewController *target, NSUInteger depth)
{
    if (!controller || !target || depth > 12)
        return nil;
    if ([controller isKindOfClass:[UINavigationController class]])
    {
        UINavigationController *navigationController = (UINavigationController *) controller;
        if ([navigationController.viewControllers containsObject:target])
            return navigationController;
        for (UIViewController *child in navigationController.viewControllers)
        {
            UINavigationController *result =
                SettingsNavigationControllerContaining(child, target, depth + 1);
            if (result)
                return result;
        }
    }
    if (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed)
    {
        UINavigationController *result = SettingsNavigationControllerContaining(
            controller.presentedViewController, target, depth + 1);
        if (result)
            return result;
    }
    for (UIViewController *child in controller.childViewControllers)
    {
        UINavigationController *result =
            SettingsNavigationControllerContaining(child, target, depth + 1);
        if (result)
            return result;
    }
    return nil;
}

static UINavigationController *SettingsNavigationControllerForController(
    YTSettingsViewController *controller)
{
    if (!controller)
        return nil;
    if (controller.navigationController)
        return controller.navigationController;
    for (UIViewController *parent = controller.parentViewController; parent;
         parent = parent.parentViewController)
    {
        if ([parent isKindOfClass:[UINavigationController class]])
            return (UINavigationController *) parent;
    }
    for (UIWindow *window in [UIApplication sharedApplication].windows)
    {
        UINavigationController *result = SettingsNavigationControllerContaining(
            window.rootViewController, controller, 0);
        if (result)
            return result;
    }
    return nil;
}

static void AssociateSettingsManager(YTSettingsViewController *controller,
                                     YTSettingsSectionItemManager *manager)
{
    if (!controller || !manager)
        return;
    objc_setAssociatedObject(controller, SettingsControllerKey, manager,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(manager, SettingsManagerKey, controller,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (controller.navigationController)
        objc_setAssociatedObject(controller.navigationController, SettingsControllerKey, manager,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static YTSettingsSectionItemManager *SettingsManagerForController(
    YTSettingsViewController *controller)
{
    if (!controller)
        return nil;
    YTSettingsSectionItemManager *manager = objc_getAssociatedObject(controller, SettingsControllerKey);
    if (!manager)
        manager = objc_getAssociatedObject(controller.navigationController, SettingsControllerKey);
    if (!manager)
    {
        manager = SettingsValue(controller, @"_sectionItemManager");
        if (!manager)
            manager = SettingsValue(controller, @"sectionItemManager");
    }
    if (manager)
        AssociateSettingsManager(controller, manager);
    return manager;
}

static YTSettingsViewController *SettingsControllerForManager(
    YTSettingsSectionItemManager *manager)
{
    if (!manager)
        return nil;
    YTSettingsViewController *controller = objc_getAssociatedObject(manager, SettingsManagerKey);
    if (controller)
        return controller;
    for (NSString *key in @[
             @"_dataDelegate", @"_settingsViewControllerDelegate", @"parentResponder"
         ])
    {
        id candidate = SettingsValue(manager, key);
        controller = SettingsController(candidate);
        if (controller)
            return controller;
        id responder = candidate;
        for (NSUInteger depth = 0; responder && depth < 8; depth++)
        {
            controller = SettingsController(responder);
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

static NSNumber *SettingsCategoryValueFromDescription(NSString *description)
{
    NSRange markerRange = [description rangeOfString:@"category_id:"];
    if (markerRange.location == NSNotFound)
        return nil;
    NSString *suffix = [description substringFromIndex:NSMaxRange(markerRange)];
    NSScanner *scanner = [NSScanner scannerWithString:suffix];
    unsigned long long value = 0;
    if (![scanner scanUnsignedLongLong:&value])
        return nil;
    return @(value);
}

static NSNumber *SettingsCategoryValue(id object)
{
    if (!object)
        return nil;
    for (NSString *key in @[
             @"category", @"categoryID", @"categoryId", @"settingsCategory"
         ])
    {
        id value = SettingsValue(object, key);
        if ([value respondsToSelector:@selector(unsignedIntegerValue)])
            return @([value unsignedIntegerValue]);
    }
    return SettingsCategoryValueFromDescription([object description] ?: @"");
}

static NSNumber *SettingsCategoryForCandidate(UIViewController *candidate)
{
    if (!candidate)
        return nil;
    for (id object in @[
             candidate, SettingsValue(candidate, @"content") ?: [NSNull null],
             SettingsValue(candidate, @"model") ?: [NSNull null]
         ])
    {
        if (object == [NSNull null])
            continue;
        NSNumber *category = SettingsCategoryValue(object);
        if (!category)
            category = SettingsCategoryValue(SettingsValue(object, @"navigationEndpoint"));
        if (category)
            return category;
    }
    return nil;
}

static BOOL SettingsCandidateIsTarget(UIViewController *candidate)
{
    Class customSettingsClass = NSClassFromString(@"DeArrowSettingsViewController");
    if (customSettingsClass && [candidate isKindOfClass:customSettingsClass])
        return NO;
    NSNumber *category = SettingsCategoryForCandidate(candidate);
    if (category)
        return category.unsignedIntegerValue == SettingsCategory;
    NSString *title = candidate.title.length > 0 ? candidate.title : candidate.navigationItem.title;
    return [title isEqualToString:@"DeArrow"];
}

static UIViewController *CustomSettingsDestination(YTSettingsViewController *controller)
{
    UIViewController *destination = CreateDeArrowSettingsViewController();
    YTSettingsSectionItemManager *manager = SettingsManagerForController(controller);
    if (manager)
        objc_setAssociatedObject(destination, SettingsControllerKey, manager,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return destination;
}

static BOOL PushCustomSettings(YTSettingsViewController *controller, BOOL animated)
{
    UINavigationController *navigationController = SettingsNavigationControllerForController(controller);
    UIViewController *destination = CustomSettingsDestination(controller);
    if (!destination)
        return NO;
    if (!navigationController)
    {
        UINavigationController *modalNavigationController =
            [[UINavigationController alloc] initWithRootViewController:destination];
        modalNavigationController.modalPresentationStyle = UIModalPresentationFullScreen;
        [controller presentViewController:modalNavigationController animated:NO completion:nil];
        return YES;
    }
    [navigationController pushViewController:destination animated:animated];
    return YES;
}

static NSMutableArray *StandaloneCategories(void)
{
    static NSMutableArray *categories;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ categories = [NSMutableArray arrayWithObject:@(SettingsCategory)]; });
    return categories;
}

static NSArray *CategoriesWithoutStandalone(NSArray *categories)
{
    if (categories.count == 0)
        return categories ?: @[];
    NSMutableArray *result = categories.mutableCopy;
    [result removeObjectsInArray:StandaloneCategories()];
    return result.copy;
}

static UIViewController *CustomSplitDestination(YTSettingsViewController *controller)
{
    UIViewController *destination = CustomSettingsDestination(controller);
    if (!destination)
        return nil;
    UINavigationController *navigationController =
        [[UINavigationController alloc] initWithRootViewController:destination];
    navigationController.navigationBarHidden = NO;
    return navigationController;
}

%group StandaloneSettings

%hook YTAppSettingsGroupPresentationData

+ (NSArray *)orderedGroups
{
    NSArray *groups = %orig;
    for (YTSettingsGroupData *group in groups)
    {
        if (group.type == SettingsGroup)
            return groups;
    }
    Class groupClass = NSClassFromString(@"YTSettingsGroupData");
    if (!groupClass)
        return groups;
    NSMutableArray *result = groups.mutableCopy ?: [NSMutableArray array];
    [result insertObject:[[groupClass alloc] initWithGroupType:SettingsGroup] atIndex:0];
    return result.copy;
}

%end

%hook YTSettingsGroupData

%new
+ (NSArray<NSNumber *> *)settingsIntegrationCategories
{
    @synchronized(StandaloneCategories())
    {
        return StandaloneCategories().copy;
    }
}

%new
+ (void)registerSettingsIntegrationCategory:(NSInteger)category
{
    NSNumber *value = @(category);
    @synchronized(StandaloneCategories())
    {
        if (![StandaloneCategories() containsObject:value])
            [StandaloneCategories() addObject:value];
    }
}

- (NSArray<NSNumber *> *)orderedCategories
{
    if (self.type == SettingsGroup)
        return StandaloneCategories().copy;
    NSArray *categories = %orig;
    return CategoriesWithoutStandalone(categories);
}

- (NSArray<NSNumber *> *)orderedCategoriesForGroupType:(NSUInteger)type
{
    if (type == SettingsGroup)
        return StandaloneCategories().copy;
    NSArray *categories = %orig;
    return CategoriesWithoutStandalone(categories);
}

- (NSArray<NSNumber *> *)accountCategories
{
    NSArray *categories = %orig;
    return CategoriesWithoutStandalone(categories);
}

- (NSArray<NSNumber *> *)appPreferenceCategories
{
    NSArray *categories = %orig;
    return CategoriesWithoutStandalone(categories);
}

- (NSArray<NSNumber *> *)videoPreferencesCategories
{
    NSArray *categories = %orig;
    return CategoriesWithoutStandalone(categories);
}

- (NSArray<NSNumber *> *)privacyCategories
{
    NSArray *categories = %orig;
    return CategoriesWithoutStandalone(categories);
}

- (NSArray<NSNumber *> *)miscellaneousCategories
{
    NSArray *categories = %orig;
    return CategoriesWithoutStandalone(categories);
}

- (NSArray<NSNumber *> *)developmentCategories
{
    NSArray *categories = %orig;
    return CategoriesWithoutStandalone(categories);
}

- (NSString *)titleForSettingGroupType:(NSUInteger)type
{
    if (type == SettingsGroup)
        return nil;
    return %orig;
}

%end

%hook YTSettingsSectionItemManager

- (id)initWithParentResponder:(id)parentResponder
                controllerDelegate:(id)controllerDelegate
                      dataDelegate:(id)dataDelegate
    settingsViewControllerDelegate:(id)settingsViewControllerDelegate
{
    id result = %orig(parentResponder, controllerDelegate, dataDelegate,
                      settingsViewControllerDelegate);
    YTSettingsViewController *controller = SettingsController(dataDelegate);
    if (!controller)
        controller = SettingsController(settingsViewControllerDelegate);
    if (!controller)
        controller = SettingsController(parentResponder);
    if (result && controller)
        AssociateSettingsManager(controller, result);
    return result;
}

- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry
{
    if (category == SettingsCategory)
    {
        YTSettingsViewController *controller = SettingsControllerForManager(self);
        if (controller)
            DeArrowConfigureSettingsSectionForController(controller);
        return;
    }
    %orig;
}

%end

%hook YTSettingsViewController

- (void)sendSettingsNavigationEndpointForCategory:(NSUInteger)category
{
    if (category == SettingsCategory && PushCustomSettings(self, YES))
        return;
    %orig(category);
}

- (void)didReceiveDrillDownItem:(id)item
{
    NSNumber *category = SettingsCategoryValue(item);
    if (category.unsignedIntegerValue == SettingsCategory && PushCustomSettings(self, YES))
        return;
    %orig(item);
}

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    if (SettingsCandidateIsTarget(viewController))
    {
        UIViewController *destination = CustomSettingsDestination(self);
        if (destination)
        {
            [self.navigationController pushViewController:destination animated:animated];
            return;
        }
    }
    %orig(viewController, animated);
}

- (void)pushViewController:(UIViewController *)viewController
{
    [self pushViewController:viewController animated:YES];
}

- (void)showOrPushViewController:(UIViewController *)viewController
{
    if (SettingsCandidateIsTarget(viewController))
    {
        UIViewController *destination = CustomSettingsDestination(self);
        if (destination)
        {
            [self.navigationController pushViewController:destination animated:YES];
            return;
        }
    }
    %orig(viewController);
}

- (void)showViewController:(UIViewController *)viewController sender:(id)sender
{
    if (SettingsCandidateIsTarget(viewController))
    {
        UIViewController *destination = CustomSettingsDestination(self);
        if (destination)
        {
            [self.navigationController pushViewController:destination animated:YES];
            return;
        }
    }
    %orig(viewController, sender);
}

%end

%hook UINavigationController

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    YTSettingsViewController *controller = SettingsControllerInViewController(self, 0);
    if (controller && SettingsCandidateIsTarget(viewController))
    {
        UIViewController *destination = CustomSettingsDestination(controller);
        if (destination)
        {
            %orig(destination, animated);
            return;
        }
    }
    %orig(viewController, animated);
}

- (void)pushViewController:(UIViewController *)viewController
{
    YTSettingsViewController *controller = SettingsControllerInViewController(self, 0);
    if (controller && SettingsCandidateIsTarget(viewController))
    {
        UIViewController *destination = CustomSettingsDestination(controller);
        if (destination)
        {
            %orig(destination);
            return;
        }
    }
    %orig(viewController);
}

- (void)showOrPushViewController:(UIViewController *)viewController
{
    YTSettingsViewController *controller = SettingsControllerInViewController(self, 0);
    if (controller && SettingsCandidateIsTarget(viewController))
    {
        UIViewController *destination = CustomSettingsDestination(controller);
        if (destination)
        {
            %orig(destination);
            return;
        }
    }
    %orig(viewController);
}

- (void)showViewController:(UIViewController *)viewController sender:(id)sender
{
    YTSettingsViewController *controller = SettingsControllerInViewController(self, 0);
    if (controller && SettingsCandidateIsTarget(viewController))
    {
        UIViewController *destination = CustomSettingsDestination(controller);
        if (destination)
        {
            [self pushViewController:destination animated:YES];
            return;
        }
    }
    %orig(viewController, sender);
}

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers
{
    YTSettingsViewController *controller = SettingsControllerInViewController(self, 0);
    if (!controller)
    {
        %orig(viewControllers);
        return;
    }
    NSMutableArray *replaced = viewControllers.mutableCopy;
    BOOL changed = NO;
    for (NSUInteger index = 0; index < replaced.count; index++)
    {
        UIViewController *candidate = replaced[index];
        if (!SettingsCandidateIsTarget(candidate))
            continue;
        UIViewController *destination = CustomSettingsDestination(controller);
        if (destination)
        {
            replaced[index] = destination;
            changed = YES;
        }
    }
    %orig(changed ? replaced : viewControllers);
}

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated
{
    YTSettingsViewController *controller = SettingsControllerInViewController(self, 0);
    if (!controller)
    {
        %orig(viewControllers, animated);
        return;
    }
    NSMutableArray *replaced = viewControllers.mutableCopy;
    BOOL changed = NO;
    for (NSUInteger index = 0; index < replaced.count; index++)
    {
        UIViewController *candidate = replaced[index];
        if (!SettingsCandidateIsTarget(candidate))
            continue;
        UIViewController *destination = CustomSettingsDestination(controller);
        if (destination)
        {
            replaced[index] = destination;
            changed = YES;
        }
    }
    %orig(changed ? replaced : viewControllers, animated);
}

%end

%hook YTWrapperSplitViewController

- (void)setSecondViewController:(UIViewController *)viewController
{
    UIViewController *master = SettingsValue(self, @"viewController");
    YTSettingsViewController *controller = SettingsControllerInViewController(master, 0);
    if (!controller)
        controller = SettingsControllerInViewController(self, 0);
    if (controller && SettingsCandidateIsTarget(viewController))
    {
        UIViewController *destination = CustomSplitDestination(controller);
        if (destination)
        {
            %orig(destination);
            return;
        }
    }
    %orig(viewController);
}

%end

%end

%ctor
{
    [[NSNotificationCenter defaultCenter]
        addObserverForName:@"SettingsIntegrationHostReady"
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(__unused NSNotification *notification) {
                    SettingsHostWasAnnounced = YES;
                }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2500 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
                       if (!SettingsHostWasAnnounced && !SettingsHostAvailable())
                           %init(StandaloneSettings);
                   });
}
