#import <UIKit/UIKit.h>
#import "NodeIntegration.h"
#import "SettingsIntegration.h"
#import "ThumbnailIntegration.h"
#import "TitleIntegration.h"

static void DeArrowInstallIntegrations(void)
{
    DeArrowInstallNodeIntegration();
    DeArrowInstallSettingsIntegration();
    DeArrowInstallThumbnailIntegration();
    DeArrowInstallTitleIntegration();
}

__attribute__((constructor)) static void DeArrowInitialize(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        DeArrowInstallIntegrations();
    });
}
