#import "TitleIntegration.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "BrandingClient.h"
#import "HookSupport.h"
#import "IntegrationSupport.h"
#import "Preferences.h"
#import "YouTube.h"

static NSAttributedString *AttributedTitleWithString(NSAttributedString *original, NSString *title)
{
    if (!title.length)
        return original;
    if (!original.length)
        return [[NSAttributedString alloc] initWithString:title];
    NSMutableAttributedString *replacement = [original mutableCopy];
    [replacement.mutableString setString:title];
    return replacement;
}

static VideoMetadataRecord *TitleMetadata(id object)
{
    return DeArrowStoredMetadataForObject(object);
}

static BOOL HasKnownTitleClass(id object)
{
    if (!object)
        return NO;
    for (Class current = object_getClass(object); current; current = class_getSuperclass(current))
    {
        if ([(@[ @"ASTextNode", @"ELMTextNode", @"YTFormattedStringLabel",
                 @"YTNewFormattedLabel" ]) containsObject:NSStringFromClass(current)])
            return YES;
    }
    return NO;
}

static BOOL TextContainsURL(NSAttributedString *value)
{
    NSString *text = value.string.lowercaseString;
    return [text containsString:@"http://"] || [text containsString:@"https://"] ||
           [text containsString:@"youtube.com/"] || [text containsString:@"youtu.be/"];
}

static void ConfigureTitleLayout(id object)
{
    if (!object)
        return;
    SEL maximumLinesSelector = NSSelectorFromString(@"setMaximumNumberOfLines:");
    if ([object respondsToSelector:maximumLinesSelector])
    {
        void (*message)(id, SEL, NSUInteger) = (void (*)(id, SEL, NSUInteger)) objc_msgSend;
        message(object, maximumLinesSelector, 0);
    }
    if ([object respondsToSelector:@selector(setNumberOfLines:)])
    {
        void (*message)(id, SEL, NSInteger) = (void (*)(id, SEL, NSInteger)) objc_msgSend;
        message(object, @selector(setNumberOfLines:), 0);
    }
    if ([object respondsToSelector:@selector(setLineBreakMode:)])
    {
        void (*message)(id, SEL, NSLineBreakMode) =
            (void (*)(id, SEL, NSLineBreakMode)) objc_msgSend;
        message(object, @selector(setLineBreakMode:), NSLineBreakByWordWrapping);
    }
}

static void ApplyTitleValue(id object, NSAttributedString *value)
{
    BrandingBinding *binding = DeArrowBindingForObject(object, YES);
    ConfigureTitleLayout(object);
    binding.applyingTitle = YES;
    [object setAttributedText:value];
    binding.applyingTitle = NO;
}

static void RequestTitle(id object, BrandingBinding *binding)
{
    DeArrowPreferences *preferences = [DeArrowPreferences sharedPreferences];
    if (!preferences.isEnabled || preferences.titlePreference != DeArrowTitlePreferenceDeArrow)
        return;
    NSString *videoID = binding.metadata.videoID;
    if (!videoID.length || binding.brandingToken || binding.brandingResolved ||
        binding.brandingRetryTime > [NSDate date].timeIntervalSince1970)
        return;
    NSUInteger              generation  = binding.generation;
    __weak id               weakObject  = object;
    __weak BrandingBinding *weakBinding = binding;
    binding.brandingToken               = [[BrandingClient sharedClient]
        requestBrandingForVideoID:videoID
                       completion:^(BrandingRecord *record, NSError *error) {
                           dispatch_async(dispatch_get_main_queue(), ^{
                               id               strongObject  = weakObject;
                               BrandingBinding *strongBinding = weakBinding;
                               if (!strongObject || !strongBinding ||
                                   strongBinding.generation != generation ||
                                   ![strongBinding.metadata.videoID isEqualToString:videoID])
                                   return;
                               strongBinding.brandingToken    = nil;
                               strongBinding.brandingResolved = error == nil;
                               strongBinding.brandingRetryTime =
                                   error ? [NSDate date].timeIntervalSince1970 + 10.0 : 0.0;
                               if (![DeArrowPreferences sharedPreferences].isEnabled ||
                                   [DeArrowPreferences sharedPreferences].titlePreference !=
                                       DeArrowTitlePreferenceDeArrow)
                                   return;
                               if (record.title.length && strongBinding.originalTitle.length)
                               {
                                   NSAttributedString *replacement = AttributedTitleWithString(
                                       strongBinding.originalTitle, record.title);
                                   ApplyTitleValue(strongObject, replacement);
                               }
                           });
                       }];
}

void DeArrowRefreshTitleObject(id object)
{
    if (!object)
        return;
    if (!NSThread.isMainThread)
    {
        __weak id weakObject = object;
        dispatch_async(dispatch_get_main_queue(), ^{
            id strongObject = weakObject;
            if (strongObject)
                DeArrowRefreshTitleObject(strongObject);
        });
        return;
    }
    BrandingBinding *binding = DeArrowBindingForObject(object, NO);
    if (!binding)
        return;
    VideoMetadataRecord *metadata = TitleMetadata(object);
    if (!metadata || !binding.originalTitle.length)
        return;
    DeArrowPreferences *preferences = [DeArrowPreferences sharedPreferences];
    if (!preferences.isEnabled || preferences.titlePreference != DeArrowTitlePreferenceDeArrow)
    {
        [binding.brandingToken cancel];
        binding.brandingToken     = nil;
        binding.brandingResolved  = NO;
        binding.brandingRetryTime = 0.0;
    }
    BrandingRecord *record =
        preferences.isEnabled && preferences.titlePreference == DeArrowTitlePreferenceDeArrow
            ? [[BrandingClient sharedClient] cachedBrandingForVideoID:metadata.videoID]
            : nil;
    if (record.title.length)
        ApplyTitleValue(object, AttributedTitleWithString(binding.originalTitle, record.title));
    else
        ApplyTitleValue(object, binding.originalTitle);
    RequestTitle(object, binding);
}

static NSArray *TitleChildren(id object)
{
    if (!object || ![object respondsToSelector:NSSelectorFromString(@"yogaChildren")])
        return nil;
    @try
    {
        id children = [object valueForKey:@"yogaChildren"];
        if ([children isKindOfClass:[NSArray class]])
            return children;
    }
    @catch (__unused NSException *exception)
    {
    }
    return nil;
}

static BOOL IsTitleObject(id object)
{
    return object && [object respondsToSelector:@selector(attributedText)] &&
           [object respondsToSelector:@selector(setAttributedText:)];
}

static BOOL IsPlayerController(UIViewController *controller)
{
    if (!controller)
        return NO;
    NSArray<NSString *> *classNames = @[
        @"YTPlayerViewController", @"YTReelPlayerViewController", @"YTShortsPlayerViewController",
        @"YTWatchViewController", @"YTWatchController"
    ];
    for (Class current = object_getClass(controller); current;
         current       = class_getSuperclass(current))
    {
        if ([classNames containsObject:NSStringFromClass(current)])
            return YES;
    }
    return NO;
}

static UIViewController *PlayerControllerForObject(id object)
{
    if (!object)
        return nil;
    UIViewController *controller = nil;
    if ([object isKindOfClass:[UIViewController class]])
        controller = object;
    else if ([object isKindOfClass:[UIView class]] &&
             [object respondsToSelector:@selector(_viewControllerForAncestor)])
        controller = [(UIView *) object _viewControllerForAncestor];
    for (NSUInteger depth = 0; controller && depth < 8; depth++)
    {
        if (IsPlayerController(controller))
            return controller;
        controller = controller.parentViewController;
    }
    return nil;
}

static void CaptureTitleObject(id object, VideoMetadataRecord *metadata)
{
    if (!IsTitleObject(object) || !HasKnownTitleClass(object) || !metadata.videoID.length)
        return;
    NSAttributedString *value = [object attributedText];
    if (TextContainsURL(value))
        return;
    DeArrowAssociateMetadata(object, metadata);
    BrandingBinding *binding = DeArrowBindingForObject(object, YES);
    if (!binding.originalTitle)
    {
        if (value.length)
            binding.originalTitle = [value copy];
    }
    if (binding.originalTitle.length)
    {
        DeArrowRegisterTitleObject(object);
        DeArrowRefreshTitleObject(object);
    }
}

static void CapturePlayerTitleViews(UIView *view, VideoMetadataRecord *metadata, NSUInteger depth)
{
    if (!view || !metadata || depth > 12)
        return;
    if (IsTitleObject(view) && HasKnownTitleClass(view))
        CaptureTitleObject(view, metadata);
    for (UIView *child in view.subviews)
        CapturePlayerTitleViews(child, metadata, depth + 1);
}

static void SchedulePlayerTitleRefresh(id player)
{
    if (![player isKindOfClass:[UIViewController class]])
        return;
    if (!NSThread.isMainThread)
    {
        __weak id weakPlayer = player;
        dispatch_async(dispatch_get_main_queue(), ^{
            id strongPlayer = weakPlayer;
            if (strongPlayer)
                SchedulePlayerTitleRefresh(strongPlayer);
        });
        return;
    }
    UIView *view = [(UIViewController *) player viewIfLoaded];
    if (!view ||
        [objc_getAssociatedObject(player, @selector(SchedulePlayerTitleRefresh)) boolValue])
        return;
    objc_setAssociatedObject(player, @selector(SchedulePlayerTitleRefresh), @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak id weakPlayer = player;
    dispatch_async(dispatch_get_main_queue(), ^{
        id strongPlayer = weakPlayer;
        if (strongPlayer)
        {
            objc_setAssociatedObject(strongPlayer, @selector(SchedulePlayerTitleRefresh), @NO,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            VideoMetadataRecord *metadata    = DeArrowStoredMetadataForObject(strongPlayer);
            UIView              *currentView = [(UIViewController *) strongPlayer viewIfLoaded];
            if (metadata && currentView)
                CapturePlayerTitleViews(currentView, metadata, 0);
        }
    });
}

static void ObservePlayerMetadata(id player, VideoMetadataRecord *metadata)
{
    if (!player || !metadata.videoID.length)
        return;
    if (!NSThread.isMainThread)
    {
        __weak id            weakPlayer     = player;
        VideoMetadataRecord *strongMetadata = [metadata copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            id strongPlayer = weakPlayer;
            if (strongPlayer)
                ObservePlayerMetadata(strongPlayer, strongMetadata);
        });
        return;
    }
    NSString *previousVideoID = objc_getAssociatedObject(player, @selector(ObservePlayerMetadata));
    if (![previousVideoID isEqualToString:metadata.videoID])
    {
        objc_setAssociatedObject(player, @selector(ObservePlayerMetadata), metadata.videoID,
                                 OBJC_ASSOCIATION_COPY_NONATOMIC);
        DeArrowAssociateMetadata(player, metadata);
    }
    else if (!DeArrowStoredMetadataForObject(player))
        DeArrowAssociateMetadata(player, metadata);
    SchedulePlayerTitleRefresh(player);
}

static void ObservePlayer(id player)
{
    VideoMetadataRecord *metadata = [VideoMetadataAdapters recordForObject:player];
    if (metadata)
        ObservePlayerMetadata(player, metadata);
}

static void ObservePlayerVideoID(id player, id value)
{
    if (![value isKindOfClass:[NSString class]])
        return;
    NSString *previousVideoID = objc_getAssociatedObject(player, @selector(ObservePlayerMetadata));
    if ([previousVideoID isEqualToString:value] && DeArrowStoredMetadataForObject(player))
        return;
    VideoMetadataRecord *metadata = [VideoMetadataAdapters recordForObject:@{@"videoId" : value}];
    if (metadata)
        ObservePlayerMetadata(player, metadata);
}

static void RefreshTitleTree(id object, NSUInteger depth)
{
    if (!object || depth > 12)
        return;
    VideoMetadataRecord *metadata = DeArrowStoredMetadataForObject(object);
    if (!metadata)
        return;
    for (id child in TitleChildren(object))
    {
        CaptureTitleObject(child, metadata);
        RefreshTitleTree(child, depth + 1);
    }
}

void DeArrowRefreshTitleTree(id object)
{
    if (!object)
        return;
    if (!NSThread.isMainThread)
    {
        __weak id weakObject = object;
        dispatch_async(dispatch_get_main_queue(), ^{
            id strongObject = weakObject;
            if (strongObject)
                DeArrowRefreshTitleTree(strongObject);
        });
        return;
    }
    RefreshTitleTree(object, 0);
}

static VideoMetadataRecord *MetadataForTitleObject(id object)
{
    VideoMetadataRecord *metadata = DeArrowStoredMetadataForObject(object);
    if (metadata)
        return metadata;
    UIViewController *player = PlayerControllerForObject(object);
    metadata                 = DeArrowStoredMetadataForObject(player);
    if (metadata)
        DeArrowAssociateMetadata(object, metadata);
    return metadata;
}

static void HandleAttributedTitle(id object, SEL selector, NSAttributedString *value, IMP original)
{
    BrandingBinding *binding = DeArrowBindingForObject(object, NO);
    if (binding && binding.applyingTitle)
    {
        ((void (*)(id, SEL, NSAttributedString *)) original)(object, selector, value);
        return;
    }
    if (TextContainsURL(value))
    {
        ((void (*)(id, SEL, NSAttributedString *)) original)(object, selector, value);
        return;
    }
    VideoMetadataRecord *metadata = MetadataForTitleObject(object);
    if (!metadata || !metadata.videoID.length)
    {
        ((void (*)(id, SEL, NSAttributedString *)) original)(object, selector, value);
        return;
    }
    DeArrowAssociateMetadata(object, metadata);
    binding = DeArrowBindingForObject(object, YES);
    if (!binding.originalTitle.length && value.length)
        binding.originalTitle = [value copy];
    if (!binding.originalTitle.length)
    {
        ((void (*)(id, SEL, NSAttributedString *)) original)(object, selector, value);
        return;
    }
    DeArrowRegisterTitleObject(object);
    DeArrowPreferences *preferences = [DeArrowPreferences sharedPreferences];
    BrandingRecord     *record =
        preferences.isEnabled && preferences.titlePreference == DeArrowTitlePreferenceDeArrow
            ? [[BrandingClient sharedClient] cachedBrandingForVideoID:metadata.videoID]
            : nil;
    NSAttributedString *replacement =
        record.title.length ? AttributedTitleWithString(binding.originalTitle, record.title)
                            : value;
    ((void (*)(id, SEL, NSAttributedString *)) original)(object, selector, replacement);
    RequestTitle(object, binding);
}

static void HandlePlainTitle(id object, SEL selector, NSString *text, IMP original)
{
    ((void (*)(id, SEL, NSString *)) original)(object, selector, text);
    BrandingBinding *binding = DeArrowBindingForObject(object, NO);
    if (binding && binding.applyingTitle)
        return;
    VideoMetadataRecord *metadata = MetadataForTitleObject(object);
    if (!metadata || !metadata.videoID.length ||
        TextContainsURL([[NSAttributedString alloc] initWithString:text ?: @""]))
        return;
    DeArrowAssociateMetadata(object, metadata);
    binding = DeArrowBindingForObject(object, YES);
    if (!binding.originalTitle.length && text.length)
        binding.originalTitle = [[NSAttributedString alloc] initWithString:text];
    if (binding.originalTitle.length)
    {
        DeArrowRegisterTitleObject(object);
        RequestTitle(object, binding);
    }
}

static void InstallTitleLabelHook(Class targetClass, SEL selector, BOOL plainText)
{
    Method method = targetClass ? class_getInstanceMethod(targetClass, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 3)
        return;
    char argumentType[128] = {0};
    method_getArgumentType(method, 2, argumentType, sizeof(argumentType));
    if (argumentType[0] != '@')
        return;
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        if (plainText)
        {
            return ^(id object, SEL selector, NSString *text) {
                HandlePlainTitle(object, selector, text, original);
            };
        }
        return ^(id object, SEL selector, NSAttributedString *value) {
            HandleAttributedTitle(object, selector, value, original);
        };
    });
}

static void InstallPlayerVideoIDHook(Class targetClass, SEL selector)
{
    if (!targetClass || !class_getInstanceMethod(targetClass, selector))
        return;
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^id(id object, SEL selector) {
            id value = ((id (*)(id, SEL)) original)(object, selector);
            ObservePlayerVideoID(object, value);
            return value;
        };
    });
}

static void InstallPlayerTransitionHook(Class targetClass, SEL selector)
{
    if (!targetClass || !class_getInstanceMethod(targetClass, selector))
        return;
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^(id object, SEL selector, id value) {
            ((void (*)(id, SEL, id)) original)(object, selector, value);
            ObservePlayer(object);
        };
    });
}

static void InstallPlayerAppearanceHook(Class targetClass)
{
    SEL selector = @selector(viewDidAppear:);
    if (!targetClass || !class_getInstanceMethod(targetClass, selector))
        return;
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^(id object, SEL selector, BOOL animated) {
            ((void (*)(id, SEL, BOOL)) original)(object, selector, animated);
            ObservePlayer(object);
        };
    });
}

void DeArrowInstallTitleIntegration(void)
{
    for (NSString *className in @[ @"YTNewFormattedLabel" ])
    {
        Class titleClass = NSClassFromString(className);
        if (titleClass)
            InstallTitleLabelHook(titleClass, @selector(setAttributedText:), NO);
    }
    for (NSString *className in @[
             @"YTPlayerViewController", @"YTReelPlayerViewController",
             @"YTShortsPlayerViewController", @"YTWatchViewController", @"YTWatchController"
         ])
    {
        Class playerClass = NSClassFromString(className);
        if (!playerClass)
            continue;
        InstallPlayerVideoIDHook(playerClass, NSSelectorFromString(@"currentVideoID"));
        InstallPlayerVideoIDHook(playerClass, NSSelectorFromString(@"contentVideoID"));
        InstallPlayerVideoIDHook(playerClass, NSSelectorFromString(@"videoId"));
        for (NSString *selectorName in @[
                 @"setCurrentVideo:", @"setVideo:", @"setCurrentVideoID:", @"setCurrentVideoId:",
                 @"setContentVideoID:", @"setContentVideoId:", @"setVideoId:", @"setVideoID:"
             ])
            InstallPlayerTransitionHook(playerClass, NSSelectorFromString(selectorName));
        InstallPlayerAppearanceHook(playerClass);
    }
}
