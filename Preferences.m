#import "Preferences.h"

#import "BrandingClient.h"

NSString *const DeArrowPreferencesDidChangeNotification = @"dev.adrian.dearrow.preferences.didChange";

static NSString *const DeArrowPreferenceEnabledKey = @"enabled";
static NSString *const DeArrowPreferenceTitleKey = @"titlePreference";
static NSString *const DeArrowPreferenceThumbnailsKey = @"replaceThumbnails";

@interface DeArrowPreferences ()
@property(nonatomic, strong) NSUserDefaults *defaults;
@end

@implementation DeArrowPreferences

+ (instancetype)sharedPreferences {
    static DeArrowPreferences *preferences;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        preferences = [self new];
    });
    return preferences;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _defaults = [[NSUserDefaults alloc] initWithSuiteName:@"dev.adrian.dearrow"] ?: [NSUserDefaults standardUserDefaults];
        [_defaults registerDefaults:@{
            DeArrowPreferenceEnabledKey: @YES,
            DeArrowPreferenceTitleKey: @(DeArrowTitlePreferenceDeArrow),
            DeArrowPreferenceThumbnailsKey: @YES
        }];
    }
    return self;
}

- (BOOL)isEnabled {
    return [self.defaults boolForKey:DeArrowPreferenceEnabledKey];
}

- (void)setEnabled:(BOOL)enabled {
    if (self.enabled == enabled)
        return;
    [self.defaults setBool:enabled forKey:DeArrowPreferenceEnabledKey];
    [self.defaults synchronize];
    [self postChange];
}

- (DeArrowTitlePreference)titlePreference {
    NSInteger value = [self.defaults integerForKey:DeArrowPreferenceTitleKey];
    return value == DeArrowTitlePreferenceOriginal ? DeArrowTitlePreferenceOriginal : DeArrowTitlePreferenceDeArrow;
}

- (void)setTitlePreference:(DeArrowTitlePreference)titlePreference {
    DeArrowTitlePreference value = titlePreference == DeArrowTitlePreferenceOriginal ? DeArrowTitlePreferenceOriginal : DeArrowTitlePreferenceDeArrow;
    if (self.titlePreference == value)
        return;
    [self.defaults setInteger:value forKey:DeArrowPreferenceTitleKey];
    [self.defaults synchronize];
    [self postChange];
}

- (BOOL)replaceThumbnails {
    return [self.defaults boolForKey:DeArrowPreferenceThumbnailsKey];
}

- (void)setReplaceThumbnails:(BOOL)replaceThumbnails {
    if (self.replaceThumbnails == replaceThumbnails)
        return;
    [self.defaults setBool:replaceThumbnails forKey:DeArrowPreferenceThumbnailsKey];
    [self.defaults synchronize];
    [self postChange];
}

- (NSString *)installedVersion {
#ifdef PACKAGE_VERSION
    return PACKAGE_VERSION;
#else
    return @"1.0.0";
#endif
}

- (void)postChange {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:DeArrowPreferencesDidChangeNotification object:self];
    });
}

- (void)clearCache {
    [[BrandingClient sharedClient] clearCache];
}

@end
