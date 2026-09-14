#import <UIKit/UIKit.h>

#import "SettingsIntegration.h"
#import "YouTube.h"

%hook YTIIcon

- (UIImage *)iconImageWithColor:(UIColor *)color
{
    UIImage *image = self.iconType == 1174 ? SettingsIconImage() : nil;
    return image ?: %orig;
}

- (UIImage *)iconImageWithSelected:(BOOL)selected
{
    UIImage *image = self.iconType == 1174 ? SettingsIconImage() : nil;
    return image ?: %orig;
}

%end
