#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class YTSettingsSectionItemManager;
@class YTSettingsViewController;

void DeArrowInstallSettingsIntegration(void);
void DeArrowConfigureSettingsSection(YTSettingsSectionItemManager *manager);
void DeArrowConfigureSettingsSectionForController(YTSettingsViewController *controller);
UIImage *SettingsIconImage(void);
