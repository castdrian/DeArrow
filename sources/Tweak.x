#import <UIKit/UIKit.h>

#import "NodeIntegration.h"
#import "SettingsIntegration.h"
#import "ThumbnailIntegration.h"
#import "TitleIntegration.h"
#import "UpdateChecker.h"

static void DeArrowInstallIntegrations(void)
{
    DeArrowInstallSettingsIntegration();
}

static void DeArrowInstallLateIntegrations(void)
{
    DeArrowInstallNodeIntegration();
    DeArrowInstallPlayerIntegration();
    DeArrowInstallTitleIntegration();
    DeArrowInstallThumbnailIntegration();
}

static void DeArrowScheduleLateIntegrations(void)
{
    for (NSNumber *delayValue in @[ @0.5, @2.0, @5.0, @10.0, @20.0 ])
    {
        NSTimeInterval delay = delayValue.doubleValue;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ DeArrowInstallLateIntegrations(); });
    }
}

__attribute__((constructor)) static void DeArrowInitialize(void)
{
    DeArrowInstallIntegrations();
    DeArrowInstallPlayerIntegration();
    DeArrowInstallTitleIntegration();
    DeArrowInstallThumbnailIntegration();
    dispatch_async(dispatch_get_main_queue(), ^{
        DeArrowStartUpdateChecker();
        DeArrowScheduleLateIntegrations();
    });
}
