#import <UIKit/UIKit.h>

#import "SettingsIntegration.h"
#import "YouTube.h"

%hook YTIIcon

- (UIImage *)iconImageWithColor:(UIColor *)color
{
    UIImage *image = self.iconType == 0x64617269 ? SettingsIconImage() : nil;
    return image ?: %orig;
}

- (UIImage *)iconImageWithSelected:(BOOL)selected
{
    UIImage *image = self.iconType == 0x64617269 ? SettingsIconImage() : nil;
    return image ?: %orig;
}

%end
