#import "TitleIntegration.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "BrandingClient.h"
#import "HookSupport.h"
#import "IntegrationSupport.h"
#import "Preferences.h"

static NSAttributedString *AttributedTitleWithString(NSAttributedString *original, NSString *title) {
    if (!title.length)
        return original;
    if (!original.length)
        return [[NSAttributedString alloc] initWithString:title];
    NSMutableAttributedString *replacement = [original mutableCopy];
    [replacement.mutableString setString:title];
    return replacement;
}

static VideoMetadataRecord *TitleMetadata(id object) {
    VideoMetadataRecord *metadata = DeArrowStoredMetadataForObject(object);
    if (metadata)
        return metadata;
    metadata = DeArrowMetadataFromParents(object);
    if (metadata)
        DeArrowAssociateMetadata(object, metadata);
    return metadata;
}

static void ApplyTitleValue(id object, NSAttributedString *value) {
    BrandingBinding *binding = DeArrowBindingForObject(object, YES);
    binding.applyingTitle = YES;
    [object setAttributedText:value];
    binding.applyingTitle = NO;
}

static void RequestTitle(id object, BrandingBinding *binding) {
    DeArrowPreferences *preferences = [DeArrowPreferences sharedPreferences];
    if (!preferences.isEnabled || preferences.titlePreference != DeArrowTitlePreferenceDeArrow)
        return;
    NSString *videoID = binding.metadata.videoID;
    if (!videoID.length || binding.brandingToken || binding.brandingResolved ||
        binding.brandingRetryTime > [NSDate date].timeIntervalSince1970)
        return;
    NSUInteger generation = binding.generation;
    __weak id weakObject = object;
    __weak BrandingBinding *weakBinding = binding;
    binding.brandingToken = [[BrandingClient sharedClient] requestBrandingForVideoID:videoID
                                                                             completion:^(BrandingRecord *record, NSError *error) {
        id strongObject = weakObject;
        BrandingBinding *strongBinding = weakBinding;
        if (!strongObject || !strongBinding || strongBinding.generation != generation ||
            ![strongBinding.metadata.videoID isEqualToString:videoID])
            return;
        strongBinding.brandingToken = nil;
        strongBinding.brandingResolved = error == nil;
        strongBinding.brandingRetryTime = error ? [NSDate date].timeIntervalSince1970 + 10.0 : 0.0;
        if (![DeArrowPreferences sharedPreferences].isEnabled ||
            [DeArrowPreferences sharedPreferences].titlePreference != DeArrowTitlePreferenceDeArrow)
            return;
        if (record.title.length && strongBinding.originalTitle.length)
            ApplyTitleValue(strongObject, AttributedTitleWithString(strongBinding.originalTitle, record.title));
    }];
}

void DeArrowRefreshTitleObject(id object) {
    if (!object)
        return;
    BrandingBinding *binding = DeArrowBindingForObject(object, NO);
    if (!binding)
        return;
    VideoMetadataRecord *metadata = TitleMetadata(object);
    if (!metadata || !binding.originalTitle.length)
        return;
    DeArrowPreferences *preferences = [DeArrowPreferences sharedPreferences];
    if (!preferences.isEnabled || preferences.titlePreference != DeArrowTitlePreferenceDeArrow) {
        [binding.brandingToken cancel];
        binding.brandingToken = nil;
        binding.brandingResolved = NO;
        binding.brandingRetryTime = 0.0;
    }
    BrandingRecord *record = preferences.isEnabled && preferences.titlePreference == DeArrowTitlePreferenceDeArrow
        ? [[BrandingClient sharedClient] cachedBrandingForVideoID:metadata.videoID]
        : nil;
    if (record.title.length)
        ApplyTitleValue(object, AttributedTitleWithString(binding.originalTitle, record.title));
    else
        ApplyTitleValue(object, binding.originalTitle);
    RequestTitle(object, binding);
}

static void HandleAttributedText(id object, SEL selector, NSAttributedString *value, IMP original) {
    BrandingBinding *binding = DeArrowBindingForObject(object, YES);
    if (binding.applyingTitle) {
        ((void (*)(id, SEL, NSAttributedString *))original)(object, selector, value);
        return;
    }
    VideoMetadataRecord *metadata = TitleMetadata(object);
    if (!metadata || !metadata.videoID.length) {
        ((void (*)(id, SEL, NSAttributedString *))original)(object, selector, value);
        return;
    }
    if (value)
        binding.originalTitle = [value copy];
    DeArrowRegisterTitleObject(object);
    DeArrowPreferences *preferences = [DeArrowPreferences sharedPreferences];
    BrandingRecord *record = preferences.isEnabled && preferences.titlePreference == DeArrowTitlePreferenceDeArrow
        ? [[BrandingClient sharedClient] cachedBrandingForVideoID:metadata.videoID]
        : nil;
    NSAttributedString *replacement = record.title.length && binding.originalTitle.length
        ? AttributedTitleWithString(binding.originalTitle, record.title)
        : value;
    ((void (*)(id, SEL, NSAttributedString *))original)(object, selector, replacement);
    RequestTitle(object, binding);
}

static void InstallAttributedTextHook(Class targetClass) {
    SEL selector = @selector(setAttributedText:);
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^(id object, SEL selector, NSAttributedString *value) {
            HandleAttributedText(object, selector, value, original);
        };
    });
}

static void InstallPlayerVideoGetter(Class targetClass, SEL selector) {
    DeArrowInstallInstanceHook(targetClass, selector, ^id(IMP original, SEL command) {
        return ^id(id object, SEL selector) {
            id result = ((id (*)(id, SEL))original)(object, selector);
            VideoMetadataRecord *metadata = [VideoMetadataAdapters recordForObject:result];
            if (!metadata && [result isKindOfClass:[NSString class]]) {
                NSString *videoID = [VideoMetadataAdapters videoIDFromURL:result];
                if (!videoID.length && [(NSString *)result length] == 11)
                    videoID = (NSString *)result;
                if (videoID.length)
                    metadata = [[VideoMetadataRecord alloc] initWithVideoID:videoID title:nil channel:nil];
            }
            if (metadata)
                DeArrowAssociateMetadata(object, metadata);
            return result;
        };
    });
}

void DeArrowInstallTitleIntegration(void) {
    for (NSString *className in @[@"ELMTextNode", @"ASTextNode", @"YTFormattedStringLabel"]) {
        Class textClass = NSClassFromString(className);
        if (textClass)
            InstallAttributedTextHook(textClass);
    }

    for (NSString *className in @[@"YTPlayerViewController", @"YTReelPlayerViewController", @"YTShortsPlayerViewController"]) {
        Class playerClass = NSClassFromString(className);
        if (!playerClass)
            continue;
        InstallPlayerVideoGetter(playerClass, NSSelectorFromString(@"currentVideoID"));
        InstallPlayerVideoGetter(playerClass, NSSelectorFromString(@"contentVideoID"));
        InstallPlayerVideoGetter(playerClass, NSSelectorFromString(@"videoId"));
    }
}
