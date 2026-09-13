#import <UIKit/UIKit.h>

#import "NodeIntegration.h"
#import "ThumbnailIntegration.h"
#import "TitleIntegration.h"

static void DeArrowInstallIntegrations(void)
{
    DeArrowInstallNodeIntegration();
    DeArrowInstallThumbnailIntegration();
    DeArrowInstallTitleIntegration();
}

__attribute__((constructor)) static void DeArrowInitialize(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        DeArrowInstallIntegrations();
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *notification) {
                        DeArrowInstallIntegrations();
                    }];
    });
}
