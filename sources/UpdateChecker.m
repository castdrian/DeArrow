#import "UpdateChecker.h"

#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>

#import "Preferences.h"

static NSString *DeArrowNormalizedVersion(NSString *version)
{
    NSString *normalized = [version hasPrefix:@"v"] ? [version substringFromIndex:1] : version;
    return [normalized componentsSeparatedByString:@"-"].firstObject;
}

static NSComparisonResult DeArrowCompareVersions(NSString *first, NSString *second)
{
    NSArray<NSString *> *firstParts =
        [DeArrowNormalizedVersion(first) componentsSeparatedByString:@"."];
    NSArray<NSString *> *secondParts =
        [DeArrowNormalizedVersion(second) componentsSeparatedByString:@"."];
    for (NSUInteger index = 0; index < MAX(firstParts.count, secondParts.count); index++)
    {
        NSInteger firstValue  = index < firstParts.count ? firstParts[index].integerValue : 0;
        NSInteger secondValue = index < secondParts.count ? secondParts[index].integerValue : 0;
        if (firstValue < secondValue)
            return NSOrderedAscending;
        if (firstValue > secondValue)
            return NSOrderedDescending;
    }
    return NSOrderedSame;
}

@interface DeArrowNotificationDelegate : NSObject <UNUserNotificationCenterDelegate>
@end

@implementation DeArrowNotificationDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:
             (void (^)(UNNotificationPresentationOptions options))completionHandler
{
    completionHandler(UNNotificationPresentationOptionBanner |
                      UNNotificationPresentationOptionList | UNNotificationPresentationOptionSound);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler
{
    NSString *URLString = response.notification.request.content.userInfo[@"url"];
    NSURL *URL = [URLString isKindOfClass:[NSString class]] ? [NSURL URLWithString:URLString] : nil;
    if (URL)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] openURL:URL
                                               options:@{}
                                     completionHandler:^(__unused BOOL success) {}];
        });
    }
    completionHandler();
}

@end

static DeArrowNotificationDelegate *DeArrowNotificationDelegateInstance;

static void DeArrowScheduleUpdateNotification(NSString *version, NSString *URLString)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UNMutableNotificationContent *content = [UNMutableNotificationContent new];
        content.title                         = @"DeArrow update available";
        content.body                          = [NSString stringWithFormat:@"Version %@", version];
        content.sound                         = [UNNotificationSound defaultSound];
        content.userInfo                      = @{@"url" : URLString, @"version" : version};
        NSString *identifier = [NSString stringWithFormat:@"dearrow-update-%@", version];
        UNTimeIntervalNotificationTrigger *trigger =
            [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1.0 repeats:NO];
        UNNotificationRequest *notification =
            [UNNotificationRequest requestWithIdentifier:identifier
                                                 content:content
                                                 trigger:trigger];
        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:notification
                                                               withCompletionHandler:nil];
    });
}

static void DeArrowConfigureNotifications(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!DeArrowNotificationDelegateInstance)
        {
            DeArrowNotificationDelegateInstance = [DeArrowNotificationDelegate new];
            [UNUserNotificationCenter currentNotificationCenter].delegate =
                DeArrowNotificationDelegateInstance;
        }
        [[UNUserNotificationCenter currentNotificationCenter]
            requestAuthorizationWithOptions:UNAuthorizationOptionAlert |
                                            UNAuthorizationOptionBadge | UNAuthorizationOptionSound
                          completionHandler:^(__unused BOOL granted, __unused NSError *error) {}];
    });
}

static void DeArrowCheckLatestRelease(void)
{
    if (![DeArrowPreferences sharedPreferences].checkForUpdates)
        return;
    NSURL *URL =
        [NSURL URLWithString:@"https://api.github.com/repos/castdrian/DeArrow/releases/latest"];
    if (!URL)
        return;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"DeArrow" forHTTPHeaderField:@"User-Agent"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
          completionHandler:^(NSData *data, NSURLResponse *response, __unused NSError *error) {
              if (![response isKindOfClass:[NSHTTPURLResponse class]] ||
                  ((NSHTTPURLResponse *) response).statusCode < 200 ||
                  ((NSHTTPURLResponse *) response).statusCode >= 300 || !data)
                  return;
              NSDictionary *release = [NSJSONSerialization JSONObjectWithData:data
                                                                      options:0
                                                                        error:nil];
              if (![release isKindOfClass:[NSDictionary class]])
                  return;
              NSString *latestVersion = DeArrowNormalizedVersion(release[@"tag_name"]);
              if (latestVersion.length == 0 ||
                  DeArrowCompareVersions([DeArrowPreferences sharedPreferences].installedVersion,
                                         latestVersion) != NSOrderedAscending)
                  return;
              NSString *URLString = [release[@"html_url"] isKindOfClass:[NSString class]]
                                        ? release[@"html_url"]
                                        : @"https://github.com/castdrian/DeArrow/releases/latest";
              DeArrowScheduleUpdateNotification(latestVersion, URLString);
          }];
    [task resume];
}

void DeArrowStartUpdateChecker(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (![DeArrowPreferences sharedPreferences].checkForUpdates)
            return;
        DeArrowConfigureNotifications();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ DeArrowCheckLatestRelease(); });
    });
}
