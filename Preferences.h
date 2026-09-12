#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DeArrowTitlePreference) {
    DeArrowTitlePreferenceDeArrow = 0,
    DeArrowTitlePreferenceOriginal = 1
};

extern NSString *const DeArrowPreferencesDidChangeNotification;

@interface DeArrowPreferences : NSObject

+ (instancetype)sharedPreferences;
@property(nonatomic, getter=isEnabled) BOOL enabled;
@property(nonatomic) DeArrowTitlePreference titlePreference;
@property(nonatomic) BOOL replaceThumbnails;
@property(nonatomic, copy, readonly) NSString *installedVersion;

- (void)clearCache;

@end

NS_ASSUME_NONNULL_END
