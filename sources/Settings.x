#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import <YouTubeHeader/YTIcon.h>

#import "SettingsViewController.h"
#import "YouTube.h"

@interface YTSettingsSectionItemManager (SettingsSupport)
- (void)settingsIntegrationUpdateSectionWithEntry:(id)entry;
@end

static const NSUInteger SettingsCategory = 0x64617272;
static const NSUInteger SettingsGroup    = 0x64617270;
static const NSInteger  SettingsIconType = YT_PICTURE_IN_PICTURE;

static void *SettingsManagerControllerKey = &SettingsManagerControllerKey;
static void *SettingsControllerManagerKey = &SettingsControllerManagerKey;
static void *SettingsNavigationTokenKey   = &SettingsNavigationTokenKey;
static void *SettingsIconImageKey         = &SettingsIconImageKey;

@interface SettingsNavigationToken : NSObject
@property (nonatomic) NSUInteger category;
@property (nonatomic, weak) YTSettingsViewController *controller;
@end

@implementation SettingsNavigationToken
@end

static UIImage *SettingsIconImage(void)
{
    static UIImage        *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIImage *source = nil;
        for (NSString *path in @[
                 @"/var/jb/Library/Application Support/DeArrow.bundle/dearrow.png",
                 @"/Library/Application Support/DeArrow.bundle/dearrow.png"
             ])
        {
            source = [UIImage imageWithContentsOfFile:path];
            if (source)
                break;
        }
        if (!source)
            return;
        CGSize size = CGSizeMake(24.0, 24.0);
        UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
        [source drawInRect:CGRectMake(0.0, 0.0, size.width, size.height)];
        image = [UIGraphicsGetImageFromCurrentImageContext()
            imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        UIGraphicsEndImageContext();
    });
    return image;
}

static id SettingsIvarObject(id object, NSString *key)
{
    if (!object || key.length == 0)
        return nil;
    Ivar ivar = class_getInstanceVariable(object_getClass(object), key.UTF8String);
    if (!ivar)
        ivar = class_getInstanceVariable(object_getClass(object),
                                         [NSString stringWithFormat:@"_%@", key].UTF8String);
    const char *encoding = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if (!encoding || encoding[0] != '@')
        return nil;
    return object_getIvar(object, ivar);
}

static id SettingsObjectValue(id object, NSString *key)
{
    if (!object || key.length == 0 || object == [NSNull null])
        return nil;
    if ([object isKindOfClass:[NSDictionary class]])
        return [(NSDictionary *) object objectForKey:key];
    @try
    {
        id value = [object valueForKey:key];
        if (value)
            return value;
    }
    @catch (__unused NSException *exception)
    {
    }
    return SettingsIvarObject(object, key);
}

static YTSettingsViewController *SettingsControllerFromObject(id object)
{
    Class settingsClass = NSClassFromString(@"YTSettingsViewController");
    if (settingsClass && [object isKindOfClass:settingsClass])
        return object;
    return nil;
}

static YTSettingsViewController *SettingsControllerInHierarchy(UIViewController *controller,
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
            SettingsControllerInHierarchy(controller.presentedViewController, depth + 1);
        if (settingsController)
            return settingsController;
    }
    if ([controller isKindOfClass:[UINavigationController class]])
    {
        for (UIViewController *child in ((UINavigationController *) controller).viewControllers)
        {
            settingsController = SettingsControllerInHierarchy(child, depth + 1);
            if (settingsController)
                return settingsController;
        }
    }
    if ([controller isKindOfClass:[UISplitViewController class]])
    {
        for (UIViewController *child in ((UISplitViewController *) controller).viewControllers)
        {
            settingsController = SettingsControllerInHierarchy(child, depth + 1);
            if (settingsController)
                return settingsController;
        }
    }
    for (UIViewController *child in controller.childViewControllers)
    {
        settingsController = SettingsControllerInHierarchy(child, depth + 1);
        if (settingsController)
            return settingsController;
    }
    return nil;
}

static BOOL ViewControllerContains(UIViewController *root, UIViewController *target,
                                   NSUInteger depth)
{
    if (!root || !target || depth > 12)
        return NO;
    if (root == target)
        return YES;
    if (root.presentedViewController && !root.presentedViewController.isBeingDismissed &&
        ViewControllerContains(root.presentedViewController, target, depth + 1))
        return YES;
    for (UIViewController *child in root.childViewControllers)
    {
        if (ViewControllerContains(child, target, depth + 1))
            return YES;
    }
    return NO;
}

static UINavigationController *NavigationControllerContaining(UIViewController *root,
                                                              UIViewController *target,
                                                              NSUInteger        depth)
{
    if (!root || !target || depth > 8)
        return nil;
    if ([root isKindOfClass:[UINavigationController class]] &&
        ViewControllerContains(root, target, 0))
        return (UINavigationController *) root;
    if (root.presentedViewController && !root.presentedViewController.isBeingDismissed)
    {
        UINavigationController *navigationController =
            NavigationControllerContaining(root.presentedViewController, target, depth + 1);
        if (navigationController)
            return navigationController;
    }
    for (UIViewController *child in root.childViewControllers)
    {
        UINavigationController *navigationController =
            NavigationControllerContaining(child, target, depth + 1);
        if (navigationController)
            return navigationController;
    }
    return nil;
}

static UINavigationController *NavigationControllerForController(UIViewController *controller)
{
    if (!controller)
        return nil;
    if ([controller isKindOfClass:[UINavigationController class]])
        return (UINavigationController *) controller;
    if (controller.navigationController)
        return controller.navigationController;
    for (UIWindow *window in [UIApplication sharedApplication].windows)
    {
        UINavigationController *navigationController =
            NavigationControllerContaining(window.rootViewController, controller, 0);
        if (navigationController)
            return navigationController;
    }
    return nil;
}

static void AssociateSettingsManager(YTSettingsViewController     *controller,
                                     YTSettingsSectionItemManager *manager)
{
    if (!controller || !manager)
        return;
    objc_setAssociatedObject(controller, SettingsControllerManagerKey, manager,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(manager, SettingsManagerControllerKey, controller,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UINavigationController *navigationController = NavigationControllerForController(controller);
    if (navigationController)
        objc_setAssociatedObject(navigationController, SettingsControllerManagerKey, manager,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static YTSettingsViewController *SettingsControllerForManager(YTSettingsSectionItemManager *manager)
{
    if (!manager)
        return nil;
    YTSettingsViewController *controller =
        objc_getAssociatedObject(manager, SettingsManagerControllerKey);
    if (controller)
        return controller;
    for (NSString *key in @[ @"_dataDelegate", @"_settingsViewControllerDelegate",
                             @"parentResponder" ])
    {
        id candidate = SettingsObjectValue(manager, key);
        controller = SettingsControllerFromObject(candidate);
        if (!controller && [candidate respondsToSelector:@selector(nextResponder)])
        {
            id responder = candidate;
            for (NSUInteger depth = 0; responder && depth < 8; depth++)
            {
                controller = SettingsControllerFromObject(responder);
                if (controller)
                    break;
                responder = [responder nextResponder];
            }
        }
        if (controller)
            break;
    }
    if (!controller)
    {
        for (UIWindow *window in [UIApplication sharedApplication].windows)
        {
            controller = SettingsControllerInHierarchy(window.rootViewController, 0);
            if (controller)
                break;
        }
    }
    if (controller)
        AssociateSettingsManager(controller, manager);
    return controller;
}

static YTSettingsSectionItemManager *SettingsManagerForController(
    YTSettingsViewController *controller)
{
    if (!controller)
        return nil;
    YTSettingsSectionItemManager *manager =
        objc_getAssociatedObject(controller, SettingsControllerManagerKey);
    if (!manager)
        manager = objc_getAssociatedObject(controller.navigationController,
                                           SettingsControllerManagerKey);
    if (!manager)
    {
        for (NSString *key in @[ @"_sectionItemManager", @"sectionItemManager" ])
        {
            id candidate = SettingsObjectValue(controller, key);
            if ([candidate isKindOfClass:NSClassFromString(@"YTSettingsSectionItemManager")])
            {
                manager = candidate;
                break;
            }
        }
    }
    if (manager)
        AssociateSettingsManager(controller, manager);
    return manager;
}

static void ArmNavigationToken(YTSettingsViewController *controller)
{
    if (!controller)
        return;
    SettingsNavigationToken *token = [SettingsNavigationToken new];
    token.category = SettingsCategory;
    token.controller = controller;
    objc_setAssociatedObject(controller, SettingsNavigationTokenKey, token,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UINavigationController *navigationController = NavigationControllerForController(controller);
    if (navigationController)
        objc_setAssociatedObject(navigationController, SettingsNavigationTokenKey, token,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (objc_getAssociatedObject(controller, SettingsNavigationTokenKey) == token)
            objc_setAssociatedObject(controller, SettingsNavigationTokenKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (objc_getAssociatedObject(navigationController, SettingsNavigationTokenKey) == token)
            objc_setAssociatedObject(navigationController, SettingsNavigationTokenKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

static BOOL ConsumeNavigationToken(YTSettingsViewController *controller)
{
    SettingsNavigationToken *token =
        objc_getAssociatedObject(controller, SettingsNavigationTokenKey);
    if (!token)
        return NO;
    objc_setAssociatedObject(controller, SettingsNavigationTokenKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UINavigationController *navigationController = NavigationControllerForController(controller);
    if (objc_getAssociatedObject(navigationController, SettingsNavigationTokenKey) == token)
        objc_setAssociatedObject(navigationController, SettingsNavigationTokenKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

static SettingsNavigationToken *NavigationTokenForNavigationController(
    UINavigationController *navigationController)
{
    return objc_getAssociatedObject(navigationController, SettingsNavigationTokenKey);
}

static void InstallLegacySettingsCategoryHook(void)
{
    Class targetClass = NSClassFromString(@"YTAppSettingsPresentationData");
    SEL selector = @selector(settingsCategoryOrder);
    Method method = targetClass ? class_getClassMethod(targetClass, selector) : NULL;
    if (!method)
        return;
    static BOOL installed = NO;
    if (installed)
        return;
    IMP original = method_getImplementation(method);
    id replacement = ^id(id object, SEL command) {
        NSArray *order = ((id (*)(id, SEL)) original)(object, command);
        if ([order containsObject:@(SettingsCategory)])
            return order;
        NSMutableArray *result = order.mutableCopy ?: [NSMutableArray array];
        NSUInteger insertIndex = [order indexOfObject:@(1)];
        if (insertIndex == NSNotFound)
            [result addObject:@(SettingsCategory)];
        else
            [result insertObject:@(SettingsCategory) atIndex:insertIndex + 1];
        return result.copy;
    };
    IMP replacementImplementation = imp_implementationWithBlock(replacement);
    if (!replacementImplementation)
        return;
    method_setImplementation(method, replacementImplementation);
    installed = YES;
}

static NSNumber *SettingsCategoryValue(id object, NSUInteger depth)
{
    if (!object || object == [NSNull null] || depth > 4)
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
    NSRange marker = [description rangeOfString:@"category_id:"];
    if (marker.location == NSNotFound)
        return nil;
    NSScanner *scanner =
        [NSScanner scannerWithString:[description substringFromIndex:NSMaxRange(marker)]];
    unsigned long long category = 0;
    return [scanner scanUnsignedLongLong:&category] ? @(category) : nil;
}

static NSNumber *SettingsCategoryForCandidate(UIViewController *candidate)
{
    if (!candidate)
        return nil;
    for (id object in @[ candidate, SettingsObjectValue(candidate, @"content") ?: [NSNull null],
                         SettingsObjectValue(candidate, @"model") ?: [NSNull null],
                         SettingsObjectValue(candidate, @"navigationEndpoint") ?: [NSNull null] ])
    {
        NSNumber *category = SettingsCategoryValue(object, 0);
        if (category)
            return category;
    }
    return nil;
}

static BOOL CandidateIsSettingsCategory(UIViewController *candidate)
{
    return SettingsCategoryForCandidate(candidate).unsignedIntegerValue == SettingsCategory;
}

static UIViewController *CreateSettingsDestination(YTSettingsViewController *controller)
{
    UIViewController *custom = CreateDeArrowSettingsViewController();
    YTSettingsSectionItemManager *manager = SettingsManagerForController(controller);
    if (manager)
        objc_setAssociatedObject(custom, SettingsControllerManagerKey, manager,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return custom;
}

static BOOL PushCustomSettings(YTSettingsViewController *controller, BOOL animated)
{
    if (!controller)
        return NO;
    UINavigationController *navigationController = NavigationControllerForController(controller);
    Class customClass = NSClassFromString(@"DeArrowSettingsViewController");
    if (customClass && [navigationController.topViewController isKindOfClass:customClass])
        return YES;
    UIViewController *custom = CreateSettingsDestination(controller);
    if (!navigationController || !custom)
        return NO;
    ConsumeNavigationToken(controller);
    [navigationController pushViewController:custom animated:animated];
    return YES;
}

static UIViewController *CustomSettingsForCandidate(YTSettingsViewController *controller,
                                                    UIViewController         *candidate)
{
    if (!controller || !candidate)
        return nil;
    Class customClass = NSClassFromString(@"DeArrowSettingsViewController");
    if (customClass && [candidate isKindOfClass:customClass])
        return nil;
    SettingsNavigationToken *token =
        objc_getAssociatedObject(controller, SettingsNavigationTokenKey);
    if ((token && token.controller == controller && token.category == SettingsCategory) ||
        CandidateIsSettingsCategory(candidate))
    {
        if (token)
            ConsumeNavigationToken(controller);
        return CreateSettingsDestination(controller);
    }
    return nil;
}

static YTSettingsViewController *SettingsControllerForNavigationController(
    UINavigationController *navigationController)
{
    if (!navigationController)
        return nil;
    for (UIViewController *controller in navigationController.viewControllers.reverseObjectEnumerator)
    {
        YTSettingsViewController *settingsController =
            SettingsControllerInHierarchy(controller, 0);
        if (settingsController)
            return settingsController;
    }
    SettingsNavigationToken *token = NavigationTokenForNavigationController(navigationController);
    return token.controller;
}

static YTIIcon *SettingsIcon(void)
{
    YTIIcon *icon = [%c(YTIIcon) new];
    icon.iconType = SettingsIconType;
    UIImage *image = SettingsIconImage();
    if (image)
        objc_setAssociatedObject(icon, SettingsIconImageKey, image,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return icon;
}

%hook YTIIcon

- (UIImage *)iconImageWithColor:(UIColor *)color
{
    UIImage *image = objc_getAssociatedObject(self, SettingsIconImageKey);
    if (!image && self.iconType == SettingsIconType)
        image = SettingsIconImage();
    return image ?: %orig;
}

- (UIImage *)iconImageWithSelected:(BOOL)selected
{
    UIImage *image = objc_getAssociatedObject(self, SettingsIconImageKey);
    if (!image && self.iconType == SettingsIconType)
        image = SettingsIconImage();
    return image ?: %orig;
}

%end

static YTSettingsSectionItem *MakeSettingsItem(YTSettingsViewController *controller)
{
    Class itemClass = NSClassFromString(@"YTSettingsSectionItem");
    if (!itemClass)
        return nil;
    __weak YTSettingsViewController *weakController = controller;
    BOOL (^selectBlock)(YTSettingsCell *, NSUInteger) =
        ^BOOL(__unused YTSettingsCell *cell, __unused NSUInteger index) {
            YTSettingsViewController *strongController = weakController;
            if (!strongController)
                return NO;
            ArmNavigationToken(strongController);
            return PushCustomSettings(strongController, YES);
        };
    SEL modernSelector = @selector(itemWithTitle:titleDescription:accessibilityIdentifier:
                                   detailTextBlock:selectBlock:settingItemId:);
    if ([itemClass respondsToSelector:modernSelector])
    {
        id (*message)(id, SEL, NSString *, NSString *, NSString *, id, id, NSUInteger) =
            (id (*)(id, SEL, NSString *, NSString *, NSString *, id, id, NSUInteger)) objc_msgSend;
        return message(itemClass, modernSelector, @"DeArrow", nil,
                       @"dev.adrian.dearrow.settings", nil, selectBlock, SettingsCategory);
    }
    SEL legacySelector =
        @selector(itemWithTitle:titleDescription:accessibilityIdentifier:detailTextBlock:selectBlock:);
    if ([itemClass respondsToSelector:legacySelector])
    {
        id (*message)(id, SEL, NSString *, NSString *, NSString *, id, id) =
            (id (*)(id, SEL, NSString *, NSString *, NSString *, id, id)) objc_msgSend;
        return message(itemClass, legacySelector, @"DeArrow", nil,
                       @"dev.adrian.dearrow.settings", nil, selectBlock);
    }
    return nil;
}

static void SetSettingsSection(YTSettingsViewController     *controller,
                               YTSettingsSectionItemManager *manager)
{
    if (!controller)
        return;
    if (manager)
        AssociateSettingsManager(controller, manager);
    YTSettingsSectionItem *item = MakeSettingsItem(controller);
    if (!item)
        return;
    NSMutableArray *items = [NSMutableArray arrayWithObject:item];
    SEL modernSelector =
        @selector(setSectionItems:forCategory:title:icon:titleDescription:headerHidden:);
    if ([controller respondsToSelector:modernSelector])
    {
        void (*message)(id, SEL, NSMutableArray *, NSInteger, NSString *, YTIIcon *, NSString *,
                        BOOL) = (void (*)(id, SEL, NSMutableArray *, NSInteger, NSString *, YTIIcon *,
                                           NSString *, BOOL)) objc_msgSend;
        message(controller, modernSelector, items, SettingsCategory, @"DeArrow", SettingsIcon(),
                nil, NO);
        return;
    }
    SEL legacySelector =
        @selector(setSectionItems:forCategory:title:titleDescription:headerHidden:);
    if ([controller respondsToSelector:legacySelector])
    {
        void (*message)(id, SEL, NSMutableArray *, NSInteger, NSString *, NSString *, BOOL) =
            (void (*)(id, SEL, NSMutableArray *, NSInteger, NSString *, NSString *, BOOL)) objc_msgSend;
        message(controller, legacySelector, items, SettingsCategory, @"DeArrow", nil, NO);
    }
}

%hook YTAppSettingsGroupPresentationData

+ (NSArray *)orderedGroups
{
    NSArray *groups = %orig;
    for (YTSettingsGroupData *group in groups)
    {
        if (group.type == SettingsGroup)
            return groups;
    }
    NSMutableArray *result = groups.mutableCopy ?: [NSMutableArray array];
    [result insertObject:[[%c(YTSettingsGroupData) alloc] initWithGroupType:SettingsGroup]
                 atIndex:0];
    return result.copy;
}

%end

%hook YTSettingsGroupData

- (NSArray<NSNumber *> *)orderedCategories
{
    if (self.type == SettingsGroup)
        return @[ @(SettingsCategory) ];
    return %orig;
}

- (NSArray<NSNumber *> *)orderedCategoriesForGroupType:(NSUInteger)type
{
    if (type == SettingsGroup)
        return @[ @(SettingsCategory) ];
    return %orig;
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
    YTSettingsViewController *controller = SettingsControllerFromObject(dataDelegate);
    if (!controller)
        controller = SettingsControllerFromObject(settingsViewControllerDelegate);
    if (!controller)
        controller = SettingsControllerFromObject(parentResponder);
    if (result && controller)
        AssociateSettingsManager(controller, result);
    return result;
}

%new - (void)settingsIntegrationUpdateSectionWithEntry:(id)entry
{
    YTSettingsViewController *controller = SettingsControllerForManager(self);
    if (controller)
        SetSettingsSection(controller, self);
}

- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry
{
    if (category == SettingsCategory)
    {
        [self settingsIntegrationUpdateSectionWithEntry:entry];
        return;
    }
    %orig;
}

%end

%hook YTSettingsViewController

- (void)setSectionItems:(NSMutableArray *)items
            forCategory:(NSInteger)category
                  title:(NSString *)title
                   icon:(YTIIcon *)icon
       titleDescription:(NSString *)titleDescription
           headerHidden:(BOOL)headerHidden
{
    %orig;
    if (category == SettingsCategory)
        AssociateSettingsManager(self, SettingsManagerForController(self));
}

- (void)sendSettingsNavigationEndpointForCategory:(NSUInteger)category
{
    if (category == SettingsCategory && PushCustomSettings(self, YES))
        return;
    %orig(category);
}

- (void)didReceiveDrillDownItem:(id)item
{
    if (SettingsCategoryValue(item, 0).unsignedIntegerValue == SettingsCategory &&
        PushCustomSettings(self, YES))
        return;
    %orig(item);
}

- (void)pushViewController:(UIViewController *)viewController
{
    UIViewController *custom = CustomSettingsForCandidate(self, viewController);
    %orig(custom ?: viewController);
}

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    UIViewController *custom = CustomSettingsForCandidate(self, viewController);
    %orig(custom ?: viewController, animated);
}

- (void)showOrPushViewController:(UIViewController *)viewController
{
    UIViewController *custom = CustomSettingsForCandidate(self, viewController);
    %orig(custom ?: viewController);
}

- (void)showViewController:(UIViewController *)viewController sender:(id)sender
{
    UIViewController *custom = CustomSettingsForCandidate(self, viewController);
    %orig(custom ?: viewController, sender);
}

%end

%hook YTNavigationController

- (void)pushViewController:(UIViewController *)viewController
{
    YTSettingsViewController *controller = SettingsControllerForNavigationController(self);
    UIViewController *custom = CustomSettingsForCandidate(controller, viewController);
    %orig(custom ?: viewController);
}

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    YTSettingsViewController *controller = SettingsControllerForNavigationController(self);
    UIViewController *custom = CustomSettingsForCandidate(controller, viewController);
    %orig(custom ?: viewController, animated);
}

- (void)showOrPushViewController:(UIViewController *)viewController
{
    YTSettingsViewController *controller = SettingsControllerForNavigationController(self);
    UIViewController *custom = CustomSettingsForCandidate(controller, viewController);
    %orig(custom ?: viewController);
}

- (void)showViewController:(UIViewController *)viewController sender:(id)sender
{
    YTSettingsViewController *controller = SettingsControllerForNavigationController(self);
    UIViewController *custom = CustomSettingsForCandidate(controller, viewController);
    %orig(custom ?: viewController, sender);
}

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers
{
    YTSettingsViewController *controller = SettingsControllerForNavigationController(self);
    NSUInteger settingsIndex = [viewControllers indexOfObjectIdenticalTo:controller];
    if (settingsIndex != NSNotFound && settingsIndex + 1 < viewControllers.count)
    {
        UIViewController *custom = CustomSettingsForCandidate(controller,
                                                               viewControllers[settingsIndex + 1]);
        if (custom)
        {
            NSMutableArray *replaced = viewControllers.mutableCopy;
            replaced[settingsIndex + 1] = custom;
            %orig(replaced);
            return;
        }
    }
    %orig;
}

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated
{
    YTSettingsViewController *controller = SettingsControllerForNavigationController(self);
    NSUInteger settingsIndex = [viewControllers indexOfObjectIdenticalTo:controller];
    if (settingsIndex != NSNotFound && settingsIndex + 1 < viewControllers.count)
    {
        UIViewController *custom = CustomSettingsForCandidate(controller,
                                                               viewControllers[settingsIndex + 1]);
        if (custom)
        {
            NSMutableArray *replaced = viewControllers.mutableCopy;
            replaced[settingsIndex + 1] = custom;
            %orig(replaced, animated);
            return;
        }
    }
    %orig;
}

%end

%hook UINavigationController

- (void)pushViewController:(UIViewController *)viewController
{
    YTSettingsViewController *controller = SettingsControllerForNavigationController(self);
    UIViewController *custom = CustomSettingsForCandidate(controller, viewController);
    %orig(custom ?: viewController);
}

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    YTSettingsViewController *controller = SettingsControllerForNavigationController(self);
    UIViewController *custom = CustomSettingsForCandidate(controller, viewController);
    %orig(custom ?: viewController, animated);
}

- (void)showOrPushViewController:(UIViewController *)viewController
{
    YTSettingsViewController *controller = SettingsControllerForNavigationController(self);
    UIViewController *custom = CustomSettingsForCandidate(controller, viewController);
    %orig(custom ?: viewController);
}

- (void)showViewController:(UIViewController *)viewController sender:(id)sender
{
    YTSettingsViewController *controller = SettingsControllerForNavigationController(self);
    UIViewController *custom = CustomSettingsForCandidate(controller, viewController);
    %orig(custom ?: viewController, sender);
}

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers
{
    YTSettingsViewController *controller = SettingsControllerForNavigationController(self);
    NSUInteger settingsIndex = [viewControllers indexOfObjectIdenticalTo:controller];
    if (settingsIndex != NSNotFound && settingsIndex + 1 < viewControllers.count)
    {
        UIViewController *custom = CustomSettingsForCandidate(controller,
                                                               viewControllers[settingsIndex + 1]);
        if (custom)
        {
            NSMutableArray *replaced = viewControllers.mutableCopy;
            replaced[settingsIndex + 1] = custom;
            %orig(replaced);
            return;
        }
    }
    %orig;
}

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated
{
    YTSettingsViewController *controller = SettingsControllerForNavigationController(self);
    NSUInteger settingsIndex = [viewControllers indexOfObjectIdenticalTo:controller];
    if (settingsIndex != NSNotFound && settingsIndex + 1 < viewControllers.count)
    {
        UIViewController *custom = CustomSettingsForCandidate(controller,
                                                               viewControllers[settingsIndex + 1]);
        if (custom)
        {
            NSMutableArray *replaced = viewControllers.mutableCopy;
            replaced[settingsIndex + 1] = custom;
            %orig(replaced, animated);
            return;
        }
    }
    %orig;
}

%end

%hook YTWrapperSplitViewController

- (void)setSecondViewController:(UIViewController *)viewController
{
    YTSettingsViewController *controller = SettingsControllerInHierarchy(self, 0);
    if (controller && CandidateIsSettingsCategory(viewController))
    {
        UIViewController *custom = CreateSettingsDestination(controller);
        if (custom)
        {
            UINavigationController *navigationController =
                [[UINavigationController alloc] initWithRootViewController:custom];
            %orig(navigationController);
            return;
        }
    }
    %orig(viewController);
}

%end

%hook YTAppSettingsSectionItemActionController

- (void)displaySettingsViewController:(UIViewController *)viewController
{
    YTSettingsViewController *controller =
        SettingsControllerInHierarchy(SettingsObjectValue(self, @"viewController"), 0);
    if (!controller)
        controller = SettingsControllerInHierarchy(SettingsObjectValue(self, @"settingsViewController"), 0);
    UIViewController *custom = CustomSettingsForCandidate(controller, viewController);
    %orig(custom ?: viewController);
}

%end

%ctor
{
    %init;
    InstallLegacySettingsCategoryHook();
}
