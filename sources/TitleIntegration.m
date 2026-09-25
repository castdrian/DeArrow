#import "TitleIntegration.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

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

static void CaptureCurrentTitleObject(id object);

static BOOL IsElementsTextNode(id object)
{
    for (Class current = object_getClass(object); current; current = class_getSuperclass(current))
    {
        if ([NSStringFromClass(current) isEqualToString:@"ELMTextNode"])
            return YES;
    }
    return NO;
}

static NSMutableDictionary<NSString *, NSHashTable *> *UnresolvedTitleObjects(void)
{
    static NSMutableDictionary *objects;
    static dispatch_once_t      onceToken;
    dispatch_once(&onceToken, ^{ objects = [NSMutableDictionary dictionary]; });
    return objects;
}

static NSString *TitleLookupKey(NSString *text)
{
    NSString *trimmed =
        [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length > 0 ? trimmed.lowercaseString : nil;
}

void DeArrowRememberUnresolvedTitleObject(id object, NSString *text)
{
    if (!IsElementsTextNode(object) || text.length == 0 || text.length > 240)
        return;
    NSString *key = TitleLookupKey(text);
    if (!key.length)
        return;
    @synchronized(UnresolvedTitleObjects())
    {
        if (UnresolvedTitleObjects().count >= 1024 && !UnresolvedTitleObjects()[key])
            [UnresolvedTitleObjects()
                removeObjectForKey:UnresolvedTitleObjects().allKeys.firstObject];
        NSHashTable *objects = UnresolvedTitleObjects()[key];
        if (!objects)
        {
            objects                       = [NSHashTable weakObjectsHashTable];
            UnresolvedTitleObjects()[key] = objects;
        }
        [objects addObject:object];
    }
}

void DeArrowResolveTitleObjectsForMetadata(VideoMetadataRecord *metadata)
{
    if (!metadata.title.length)
        return;
    NSString *key = TitleLookupKey(metadata.title);
    if (!key.length)
        return;
    NSArray *objects;
    @synchronized(UnresolvedTitleObjects())
    {
        objects = [UnresolvedTitleObjects()[key].allObjects copy];
        [UnresolvedTitleObjects() removeObjectForKey:key];
    }
    if (!objects.count)
        return;
    void (^resolve)(void) = ^{
        for (id object in objects)
            DeArrowCaptureTitleObject(object, metadata);
    };
    if (NSThread.isMainThread)
        resolve();
    else
        dispatch_async(dispatch_get_main_queue(), resolve);
}

static BOOL IsElementsTitleValue(id object, NSAttributedString *value,
                                 VideoMetadataRecord *metadata)
{
    if (!IsElementsTextNode(object))
        return YES;
    NSString *candidate = [value.string
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *title     = [metadata.title
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return candidate.length > 0 && title.length > 0 &&
           [candidate caseInsensitiveCompare:title] == NSOrderedSame;
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
    if (!binding.titleLayoutConfigured)
    {
        ConfigureTitleLayout(object);
        binding.titleLayoutConfigured = YES;
    }
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

static BOOL IsTitleObject(id object)
{
    return object && [object respondsToSelector:@selector(attributedText)] &&
           [object respondsToSelector:@selector(setAttributedText:)];
}

static BOOL IsPlayerTitleCandidate(id object, VideoMetadataRecord *metadata)
{
    if (!object || !metadata.title.length || !IsTitleObject(object))
        return NO;
    NSAttributedString *value     = [object attributedText];
    NSString           *candidate = [value.string
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString           *expected  = [metadata.title
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (candidate.length < 6 || expected.length < 6)
        return NO;
    return [candidate caseInsensitiveCompare:expected] == NSOrderedSame ||
           [candidate localizedCaseInsensitiveContainsString:expected] ||
           [expected localizedCaseInsensitiveContainsString:candidate];
}

void DeArrowCaptureTitleObject(id object, VideoMetadataRecord *metadata)
{
    if (!IsTitleObject(object) || !metadata.videoID.length)
        return;
    NSAttributedString *value = [object attributedText];
    if (!IsElementsTitleValue(object, value, metadata))
        return;
    if (TextContainsURL(value))
        return;
    BrandingBinding *existingBinding = DeArrowBindingForObject(object, NO);
    if (!existingBinding.metadata ||
        ![existingBinding.metadata.videoID isEqualToString:metadata.videoID])
        DeArrowAssociateMetadata(object, metadata);
    BrandingBinding *binding = DeArrowBindingForObject(object, YES);
    if (!binding.originalTitle)
    {
        if (value.length)
            binding.originalTitle = [value copy];
    }
    if (binding.originalTitle.length)
    {
        if (!binding.titleRegistered)
        {
            DeArrowRegisterTitleObject(object);
            binding.titleRegistered = YES;
        }
        DeArrowPreferences *preferences = [DeArrowPreferences sharedPreferences];
        BrandingRecord     *record =
            preferences.isEnabled && preferences.titlePreference == DeArrowTitlePreferenceDeArrow
                ? [[BrandingClient sharedClient] cachedBrandingForVideoID:metadata.videoID]
                : nil;
        if (record.title.length)
            ApplyTitleValue(object, AttributedTitleWithString(binding.originalTitle, record.title));
        RequestTitle(object, binding);
    }
}

static VideoMetadataRecord *MetadataForTitleObject(id object, NSAttributedString *value);

static void CapturePlayerTitleViews(UIView *view, VideoMetadataRecord *metadata, NSUInteger depth)
{
    if (!view || depth > 12)
        return;
    if (metadata && IsPlayerTitleCandidate(view, metadata))
        DeArrowCaptureTitleObject(view, metadata);
    else if (IsTitleObject(view))
        CaptureCurrentTitleObject(view);
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
    for (NSNumber *delayValue in @[ @0.1, @0.7, @2.0 ])
    {
        NSTimeInterval delay = delayValue.doubleValue;
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t) (delay * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                id strongPlayer = weakPlayer;
                if (!strongPlayer)
                    return;
                objc_setAssociatedObject(strongPlayer, @selector(SchedulePlayerTitleRefresh), @NO,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                VideoMetadataRecord *metadata    = DeArrowStoredMetadataForObject(strongPlayer);
                UIView              *currentView = [(UIViewController *) strongPlayer viewIfLoaded];
                UIViewController    *ancestor =
                    [(UIViewController *) strongPlayer parentViewController];
                for (NSUInteger depth = 0; currentView && ancestor && depth < 3; depth++)
                {
                    UIView *ancestorView = [ancestor viewIfLoaded];
                    if (ancestorView)
                        currentView = ancestorView;
                    ancestor = ancestor.parentViewController;
                }
                if (metadata && currentView)
                    CapturePlayerTitleViews(currentView, metadata, 0);
            });
    }
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
    VideoMetadataRecord *existing = DeArrowStoredMetadataForObject(player);
    if (![previousVideoID isEqualToString:metadata.videoID] ||
        (metadata.title.length && !existing.title.length) ||
        (metadata.channel.length && !existing.channel.length))
    {
        objc_setAssociatedObject(player, @selector(ObservePlayerMetadata), metadata.videoID,
                                 OBJC_ASSOCIATION_COPY_NONATOMIC);
        DeArrowAssociateMetadata(player, metadata);
    }
    else if (!existing)
        DeArrowAssociateMetadata(player, metadata);
    SchedulePlayerTitleRefresh(player);
}

static void ObservePlayerVideoID(id player, id value);

static void ObservePlayerAfterAppearance(id player)
{
    if (!player)
        return;
    for (NSString *selectorName in @[ @"currentVideoID", @"contentVideoID", @"videoId" ])
    {
        SEL selector = NSSelectorFromString(selectorName);
        if (![player respondsToSelector:selector])
            continue;
        id value = nil;
        @try
        {
            value = ((id (*)(id, SEL)) objc_msgSend)(player, selector);
        }
        @catch (__unused NSException *exception)
        {
            value = nil;
        }
        if ([value isKindOfClass:[NSString class]] && [(NSString *) value length] == 11)
            ObservePlayerVideoID(player, value);
    }
    VideoMetadataRecord *metadata = DeArrowStoredMetadataForObject(player);
    if (!metadata.videoID.length)
    {
        @try
        {
            metadata = [VideoMetadataAdapters recordForObject:player];
        }
        @catch (__unused NSException *exception)
        {
            metadata = nil;
        }
    }
    if (metadata.videoID.length)
        ObservePlayerMetadata(player, metadata);
    SchedulePlayerTitleRefresh(player);
}

static void ObservePlayerVideoID(id player, id value)
{
    if (![value isKindOfClass:[NSString class]] || [(NSString *) value length] != 11)
        return;
    NSString *previousVideoID = objc_getAssociatedObject(player, @selector(ObservePlayerMetadata));
    if ([previousVideoID isEqualToString:value])
        return;
    objc_setAssociatedObject(player, @selector(ObservePlayerMetadata), value,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    VideoMetadataRecord *metadata = [VideoMetadataAdapters recordForObject:@{@"videoId" : value}];
    if (!metadata)
        metadata = [[VideoMetadataRecord alloc] initWithVideoID:value title:nil channel:nil];
    DeArrowAssociateMetadata(player, metadata);
}

static VideoMetadataRecord *MetadataForTitleObject(id object, NSAttributedString *value)
{
    VideoMetadataRecord *metadata = DeArrowStoredMetadataForObject(object);
    if (metadata)
        return metadata;
    metadata = DeArrowMetadataForTitleText(value.string);
    if (metadata)
        return metadata;
    BrandingBinding *binding    = DeArrowBindingForObject(object, YES);
    NSString        *lookupText = value.string ?: @"";
    if ([binding.metadataLookupText isEqualToString:lookupText])
        return nil;
    binding.metadataLookupText = lookupText;
    if (![object isKindOfClass:[UIView class]])
    {
        metadata = DeArrowMetadataForNodeAncestor(object);
        if (metadata)
            return metadata;
    }
    metadata = DeArrowMetadataForUIKitAncestor(object);
    if (metadata)
        return metadata;
    return nil;
}

static void CaptureCurrentTitleObject(id object)
{
    if (!IsTitleObject(object))
        return;
    NSAttributedString *value = [object attributedText];
    if (!value.length)
        return;
    VideoMetadataRecord *metadata = MetadataForTitleObject(object, value);
    if (!metadata)
    {
        DeArrowRememberUnresolvedTitleObject(object, value.string);
        return;
    }
    DeArrowCaptureTitleObject(object, metadata);
}

static void HandleAttributedTitle(id object, SEL selector, NSAttributedString *value, IMP original)
{
    BrandingBinding *binding = DeArrowBindingForObject(object, NO);
    if (binding && binding.applyingTitle)
    {
        ((void (*)(id, SEL, NSAttributedString *)) original)(object, selector, value);
        return;
    }
    VideoMetadataRecord *metadata = MetadataForTitleObject(object, value);
    if (!metadata.videoID.length || TextContainsURL(value))
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
    if (!binding.titleRegistered)
    {
        DeArrowRegisterTitleObject(object);
        binding.titleRegistered = YES;
    }
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

static IMP  OriginalFormattedTitleImplementation;
static BOOL FormattedTitleHookInstalled;

static void HookedFormattedTitle(id object, SEL selector, NSAttributedString *value)
{
    if (OriginalFormattedTitleImplementation)
        HandleAttributedTitle(object, selector, value, OriginalFormattedTitleImplementation);
}

static void InstallTitleLabelHook(Class targetClass)
{
    SEL    selector = @selector(setAttributedText:);
    Method method   = targetClass ? class_getInstanceMethod(targetClass, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 3 || FormattedTitleHookInstalled)
        return;
    char returnType[128] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    char argumentType[128] = {0};
    method_getArgumentType(method, 2, argumentType, sizeof(argumentType));
    if (returnType[0] != 'v' || argumentType[0] != '@')
        return;
    FormattedTitleHookInstalled = YES;
    MSHookMessageEx(targetClass, selector, (IMP) HookedFormattedTitle,
                    &OriginalFormattedTitleImplementation);
}

void DeArrowCaptureTitleTextObject(id object)
{
    CaptureCurrentTitleObject(object);
}

void DeArrowInstallTitleIntegration(void)
{
    Class targetClass = NSClassFromString(@"YTFormattedStringLabel");
    InstallTitleLabelHook(targetClass);
}

static void InstallPlayerVideoIDHook(Class targetClass, SEL selector)
{
    Method method = targetClass ? class_getInstanceMethod(targetClass, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 2)
        return;
    char returnType[128] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    if (returnType[0] != '@')
        return;
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^id(id object) {
            id value = ((id (*)(id, SEL)) original)(object, command);
            ObservePlayerVideoID(object, value);
            return value;
        };
    });
}

static void InstallPlayerObjectHook(Class targetClass, SEL selector)
{
    Method method = targetClass ? class_getInstanceMethod(targetClass, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 2)
        return;
    char returnType[128] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    if (returnType[0] != '@')
        return;
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^id(id object) {
            id                   value    = ((id (*)(id, SEL)) original)(object, command);
            VideoMetadataRecord *metadata = [VideoMetadataAdapters recordForObject:value];
            if (metadata)
                ObservePlayerMetadata(object, metadata);
            return value;
        };
    });
}

static void InstallPlayerTransitionHook(Class targetClass, SEL selector)
{
    Method method = targetClass ? class_getInstanceMethod(targetClass, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 3)
        return;
    char returnType[128]   = {0};
    char argumentType[128] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    method_getArgumentType(method, 2, argumentType, sizeof(argumentType));
    if (returnType[0] != 'v' || argumentType[0] != '@')
        return;
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^(id object, id value) {
            ((void (*)(id, SEL, id)) original)(object, command, value);
            VideoMetadataRecord *metadata = [VideoMetadataAdapters recordForObject:value];
            if (metadata)
                ObservePlayerMetadata(object, metadata);
            else
                ObservePlayerAfterAppearance(object);
        };
    });
}

static void InstallPlayerAppearanceHook(Class targetClass)
{
    SEL    selector = @selector(viewDidAppear:);
    Method method   = targetClass ? class_getInstanceMethod(targetClass, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 3)
        return;
    char returnType[128] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    if (returnType[0] != 'v')
        return;
    char argumentType[128] = {0};
    method_getArgumentType(method, 2, argumentType, sizeof(argumentType));
    if (argumentType[0] != 'c' && argumentType[0] != 'B')
        return;
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^(id object, BOOL animated) {
            ((void (*)(id, SEL, BOOL)) original)(object, command, animated);
            ObservePlayerAfterAppearance(object);
        };
    });
}

void DeArrowInstallPlayerIntegration(void)
{
    for (NSString *className in @[
             @"YTPlayerViewController", @"YTReelPlayerViewController",
             @"YTShortsPlayerViewController", @"YTWatchViewController", @"YTWatchController",
             @"YTWatchPlaybackController", @"YTVideoPlayerViewController"
         ])
    {
        Class playerClass = NSClassFromString(className);
        for (NSString *selectorName in @[ @"currentVideoID", @"contentVideoID", @"videoId" ])
        {
            InstallPlayerVideoIDHook(playerClass, NSSelectorFromString(selectorName));
        }
        for (NSString *selectorName in
             @[ @"currentVideo", @"currentVideoModel", @"currentVideoData", @"video" ])
            InstallPlayerObjectHook(playerClass, NSSelectorFromString(selectorName));
        for (NSString *selectorName in @[
                 @"setCurrentVideo:", @"setVideo:", @"setCurrentVideoID:", @"setCurrentVideoId:",
                 @"setContentVideoID:", @"setContentVideoId:", @"setVideoId:", @"setVideoID:"
             ])
            InstallPlayerTransitionHook(playerClass, NSSelectorFromString(selectorName));
        InstallPlayerAppearanceHook(playerClass);
    }
}
