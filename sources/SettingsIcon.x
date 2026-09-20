#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "SettingsIntegration.h"
#import "YouTube.h"

static const void *SharedSettingsIconImageKey(void)
{
    return (const void *) sel_registerName("settingsIntegrationIconImage");
}

%hook YTIIcon

- (UIImage *)iconImageWithColor:(UIColor *)color
{
    UIImage *image = objc_getAssociatedObject(self, SharedSettingsIconImageKey());
    if (!image && self.iconType == 461)
        image = SettingsIconImage();
    return image ?: %orig;
}

- (UIImage *)iconImageWithSelected:(BOOL)selected
{
    UIImage *image = objc_getAssociatedObject(self, SharedSettingsIconImageKey());
    if (!image && self.iconType == 461)
        image = SettingsIconImage();
    return image ?: %orig;
}

%end
