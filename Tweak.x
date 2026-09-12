#import "NodeIntegration.h"
#import "SettingsIntegration.h"
#import "ThumbnailIntegration.h"
#import "TitleIntegration.h"

__attribute__((constructor)) static void DeArrowInitialize(void) {
    DeArrowInstallNodeIntegration();
    DeArrowInstallTitleIntegration();
    DeArrowInstallThumbnailIntegration();
    DeArrowInstallSettingsIntegration();
}
