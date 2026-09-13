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

static NSArray *TitleChildren(id object) {
    if (!object || ![object respondsToSelector:NSSelectorFromString(@"yogaChildren")])
        return nil;
    @try {
        id children = [object valueForKey:@"yogaChildren"];
        if ([children isKindOfClass:[NSArray class]])
            return children;
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

static BOOL IsTitleObject(id object) {
    return object && [object respondsToSelector:@selector(attributedText)] &&
        [object respondsToSelector:@selector(setAttributedText:)];
}

static void CaptureTitleObject(id object, VideoMetadataRecord *metadata) {
    if (!IsTitleObject(object) || !metadata.videoID.length)
        return;
    DeArrowAssociateMetadata(object, metadata);
    BrandingBinding *binding = DeArrowBindingForObject(object, YES);
    if (!binding.originalTitle) {
        NSAttributedString *value = [object attributedText];
        if (value.length)
            binding.originalTitle = [value copy];
    }
    if (binding.originalTitle.length) {
        DeArrowRegisterTitleObject(object);
        DeArrowRefreshTitleObject(object);
    }
}

void DeArrowRefreshTitleTree(id object) {
    if (!object)
        return;
    VideoMetadataRecord *metadata = DeArrowStoredMetadataForObject(object);
    if (!metadata)
        return;
    for (id child in TitleChildren(object)) {
        CaptureTitleObject(child, metadata);
        DeArrowRefreshTitleTree(child);
    }
}

void DeArrowInstallTitleIntegration(void) {
}
