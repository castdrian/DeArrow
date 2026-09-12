#import "SettingsViewController.h"

#import <QuartzCore/QuartzCore.h>

#import "BrandingClient.h"
#import "ChangelogData.h"
#import "Preferences.h"

static NSBundle *DeArrowSettingsBundle(void) {
    static NSBundle *bundle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:@"DeArrow" ofType:@"bundle"];
        if (path.length == 0)
            path = @"/Library/Application Support/DeArrow.bundle";
        if (![[NSFileManager defaultManager] fileExistsAtPath:path])
            path = @"/var/jb/Library/Application Support/DeArrow.bundle";
        bundle = [NSBundle bundleWithPath:path];
    });
    return bundle;
}

static NSString *DeArrowLocalized(NSString *key, NSString *fallback) {
    NSString *value = [DeArrowSettingsBundle() localizedStringForKey:key value:fallback table:nil];
    return value.length > 0 ? value : fallback;
}

static NSAttributedString *RenderedDeArrowChangelog(void) {
    UIFont *bodyFont = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    UIFont *sectionFont = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
    UIFont *titleFont = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle1];
    NSMutableAttributedString *rendered = [NSMutableAttributedString new];
    for (NSString *line in [DEARROW_CHANGELOG componentsSeparatedByString:@"\n"]) {
        NSString *text = line;
        UIFont *font = bodyFont;
        CGFloat spacing = 4.0;
        if ([line hasPrefix:@"### "]) {
            text = [line substringFromIndex:4];
            font = [UIFont systemFontOfSize:sectionFont.pointSize weight:UIFontWeightBold];
            spacing = 14.0;
        } else if ([line hasPrefix:@"## "]) {
            text = [line substringFromIndex:3];
            font = [UIFont systemFontOfSize:titleFont.pointSize weight:UIFontWeightBold];
            spacing = 16.0;
        } else if ([line hasPrefix:@"# "]) {
            text = [line substringFromIndex:2];
            font = [UIFont systemFontOfSize:titleFont.pointSize + 4.0 weight:UIFontWeightBold];
            spacing = 18.0;
        } else if ([line hasPrefix:@"- "]) {
            text = [NSString stringWithFormat:@"• %@", [line substringFromIndex:2]];
        }
        NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
        paragraph.paragraphSpacing = spacing;
        if ([line hasPrefix:@"- "]) {
            paragraph.firstLineHeadIndent = 0.0;
            paragraph.headIndent = 18.0;
        }
        NSDictionary *attributes = @{NSFontAttributeName: font,
                                     NSForegroundColorAttributeName: UIColor.labelColor,
                                     NSParagraphStyleAttributeName: paragraph};
        [rendered appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", text]
                                                                            attributes:attributes]];
    }
    return rendered;
}

@interface DeArrowChangelogViewController : UIViewController
@property(nonatomic, strong) UITextView *textView;
@end

@implementation DeArrowChangelogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = DeArrowLocalized(@"WHATS_NEW", @"What’s New");
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                             target:self
                             action:@selector(close)];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.textView = [UITextView new];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.editable = NO;
    self.textView.selectable = YES;
    self.textView.alwaysBounceVertical = YES;
    self.textView.backgroundColor = UIColor.systemBackgroundColor;
    self.textView.textColor = UIColor.labelColor;
    self.textView.attributedText = RenderedDeArrowChangelog();
    [self.view addSubview:self.textView];
    [NSLayoutConstraint activateConstraints:@[
        [self.textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

static UIView *DeArrowChangelogAccessory(void) {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 72.0, 28.0)];
    UILabel *badge = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 3.0, 38.0, 22.0)];
    badge.text = DeArrowLocalized(@"NEW", @"NEW");
    badge.textColor = UIColor.whiteColor;
    badge.backgroundColor = UIColor.systemRedColor;
    badge.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightBold];
    badge.textAlignment = NSTextAlignmentCenter;
    badge.layer.cornerRadius = 8.0;
    badge.clipsToBounds = YES;
    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    chevron.frame = CGRectMake(52.0, 7.0, 14.0, 14.0);
    chevron.tintColor = UIColor.tertiaryLabelColor;
    chevron.contentMode = UIViewContentModeScaleAspectFit;
    [container addSubview:badge];
    [container addSubview:chevron];
    return container;
}

typedef NS_ENUM(NSInteger, DeArrowSettingsSection) {
    DeArrowSettingsSectionSupport,
    DeArrowSettingsSectionFiltering,
    DeArrowSettingsSectionCache,
    DeArrowSettingsSectionAbout
};

typedef NS_ENUM(NSInteger, DeArrowFilteringRow) {
    DeArrowFilteringRowEnabled,
    DeArrowFilteringRowTitle,
    DeArrowFilteringRowThumbnails
};

@interface DeArrowSettingsViewController : UITableViewController
@property(nonatomic, strong) UISwitch *enabledSwitch;
@property(nonatomic, strong) UISwitch *thumbnailSwitch;
@end

@implementation DeArrowSettingsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self)
        self.title = DeArrowLocalized(@"DEARROW", @"DeArrow");
    return self;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56.0;
    self.tableView.tableFooterView = [UIView new];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.enabledSwitch = [UISwitch new];
    self.thumbnailSwitch = [UISwitch new];
    [self.enabledSwitch addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];
    [self.thumbnailSwitch addTarget:self action:@selector(thumbnailsChanged:) forControlEvents:UIControlEventValueChanged];
    [self refreshControls];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        self.navigationItem.hidesBackButton = YES;
        self.navigationItem.leftBarButtonItem = nil;
        self.navigationItem.backBarButtonItem = nil;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        self.navigationItem.hidesBackButton = YES;
        self.navigationItem.leftBarButtonItem = nil;
        self.navigationItem.backBarButtonItem = nil;
    }
    [self refreshControls];
}

- (void)refreshControls {
    DeArrowPreferences *preferences = [DeArrowPreferences sharedPreferences];
    self.enabledSwitch.on = preferences.isEnabled;
    self.thumbnailSwitch.on = preferences.replaceThumbnails;
    [self.tableView reloadData];
}

- (void)enabledChanged:(UISwitch *)sender {
    [DeArrowPreferences sharedPreferences].enabled = sender.isOn;
}

- (void)thumbnailsChanged:(UISwitch *)sender {
    [DeArrowPreferences sharedPreferences].replaceThumbnails = sender.isOn;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == DeArrowSettingsSectionSupport)
        return 1;
    if (section == DeArrowSettingsSectionFiltering)
        return 3;
    if (section == DeArrowSettingsSectionCache)
        return 1;
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == DeArrowSettingsSectionSupport)
        return DeArrowLocalized(@"SUPPORT", @"Support");
    if (section == DeArrowSettingsSectionFiltering)
        return DeArrowLocalized(@"FILTERING", @"Filtering");
    if (section == DeArrowSettingsSectionCache)
        return DeArrowLocalized(@"CACHE", @"Cache");
    return DeArrowLocalized(@"ABOUT", @"About");
}

- (NSString *)subtitleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != DeArrowSettingsSectionFiltering)
        return nil;
    if (indexPath.row == DeArrowFilteringRowEnabled)
        return DeArrowLocalized(@"ENABLE_DEARROW_DETAIL", @"Use community-submitted titles and thumbnails");
    if (indexPath.row == DeArrowFilteringRowTitle)
        return DeArrowLocalized(@"PREFERRED_TITLE_DETAIL", @"Choose DeArrow or Original titles");
    return DeArrowLocalized(@"REPLACE_THUMBNAILS_DETAIL", @"Use community-submitted thumbnails");
}

- (UITableViewCell *)donationCellForTableView:(UITableView *)tableView {
    static NSString *identifier = @"DeArrowDonationCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    for (UIView *subview in cell.contentView.subviews)
        [subview removeFromSuperview];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *configuration = [UIButtonConfiguration tintedButtonConfiguration];
        configuration.image = [UIImage systemImageNamed:@"heart.fill"];
        configuration.title = DeArrowLocalized(@"DONATE_ON_KOFI", @"Donate on Ko-fi");
        configuration.imagePadding = 8.0;
        configuration.contentInsets = NSDirectionalEdgeInsetsMake(12.0, 12.0, 12.0, 12.0);
        configuration.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        button.configuration = configuration;
    } else {
        [button setImage:[UIImage systemImageNamed:@"heart.fill"] forState:UIControlStateNormal];
        [button setTitle:DeArrowLocalized(@"DONATE_ON_KOFI", @"Donate on Ko-fi") forState:UIControlStateNormal];
        button.imageEdgeInsets = UIEdgeInsetsMake(0.0, 0.0, 0.0, 8.0);
        button.contentEdgeInsets = UIEdgeInsetsMake(12.0, 12.0, 12.0, 12.0);
    }
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    button.accessibilityLabel = DeArrowLocalized(@"DONATE_ON_KOFI", @"Donate on Ko-fi");
    [button addTarget:self action:@selector(donateTapped:) forControlEvents:UIControlEventTouchUpInside];
    [cell.contentView addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
        [button.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4.0],
        [button.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
        [button.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
        [button.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4.0]
    ]];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = UIColor.clearColor;
    if (@available(iOS 14.0, *))
        cell.backgroundConfiguration = [UIBackgroundConfiguration clearConfiguration];
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == DeArrowSettingsSectionSupport)
        return [self donationCellForTableView:tableView];
    static NSString *identifier = @"DeArrowSettingsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.backgroundColor = UIColor.clearColor;
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    if (indexPath.section == DeArrowSettingsSectionFiltering && indexPath.row == DeArrowFilteringRowEnabled) {
        cell.textLabel.text = DeArrowLocalized(@"ENABLE_DEARROW", @"Enable DeArrow");
        cell.detailTextLabel.text = [self subtitleForRowAtIndexPath:indexPath];
        cell.accessoryView = self.enabledSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == DeArrowSettingsSectionFiltering && indexPath.row == DeArrowFilteringRowTitle) {
        cell.textLabel.text = DeArrowLocalized(@"PREFERRED_TITLE", @"Preferred title");
        NSString *value = [DeArrowPreferences sharedPreferences].titlePreference == DeArrowTitlePreferenceOriginal
            ? DeArrowLocalized(@"ORIGINAL", @"Original")
            : DeArrowLocalized(@"DEARROW", @"DeArrow");
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", [self subtitleForRowAtIndexPath:indexPath], value];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == DeArrowSettingsSectionFiltering && indexPath.row == DeArrowFilteringRowThumbnails) {
        cell.textLabel.text = DeArrowLocalized(@"REPLACE_THUMBNAILS", @"Replace thumbnails");
        cell.detailTextLabel.text = [self subtitleForRowAtIndexPath:indexPath];
        cell.accessoryView = self.thumbnailSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == DeArrowSettingsSectionCache) {
        cell.textLabel.text = DeArrowLocalized(@"CLEAR_CACHE", @"Clear branding cache");
    } else if (indexPath.row == 0) {
        cell.textLabel.text = DeArrowLocalized(@"VERSION", @"Version");
        cell.detailTextLabel.text = [DeArrowPreferences sharedPreferences].installedVersion;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.row == 1) {
        cell.textLabel.text = DeArrowLocalized(@"WHATS_NEW", @"What’s New");
        DeArrowPreferences *preferences = [DeArrowPreferences sharedPreferences];
        if (![preferences.lastViewedChangelogVersion isEqualToString:preferences.installedVersion])
            cell.accessoryView = DeArrowChangelogAccessory();
        else
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.text = DeArrowLocalized(@"GITHUB", @"DeArrow on GitHub");
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)donateTapped:(UIButton *)sender {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://ko-fi.com/castdrian"] options:@{} completionHandler:nil];
}

- (void)presentTitlePickerFromCell:(UITableViewCell *)cell {
    UIAlertController *controller = [UIAlertController alertControllerWithTitle:DeArrowLocalized(@"PREFERRED_TITLE", @"Preferred title")
                                                                           message:nil
                                                                    preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [controller addAction:[UIAlertAction actionWithTitle:DeArrowLocalized(@"DEARROW", @"DeArrow")
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(__unused UIAlertAction *action) {
        [DeArrowPreferences sharedPreferences].titlePreference = DeArrowTitlePreferenceDeArrow;
        [weakSelf refreshControls];
    }]];
    [controller addAction:[UIAlertAction actionWithTitle:DeArrowLocalized(@"ORIGINAL", @"Original")
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(__unused UIAlertAction *action) {
        [DeArrowPreferences sharedPreferences].titlePreference = DeArrowTitlePreferenceOriginal;
        [weakSelf refreshControls];
    }]];
    [controller addAction:[UIAlertAction actionWithTitle:DeArrowLocalized(@"CANCEL", @"Cancel")
                                                    style:UIAlertActionStyleCancel
                                                  handler:nil]];
    if (controller.popoverPresentationController) {
        controller.popoverPresentationController.sourceView = cell;
        controller.popoverPresentationController.sourceRect = cell.bounds;
    }
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)openChangelog {
    [[DeArrowPreferences sharedPreferences] markChangelogSeen];
    DeArrowChangelogViewController *changelog = [DeArrowChangelogViewController new];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:changelog];
    navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
    [self.tableView reloadData];
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == DeArrowSettingsSectionSupport) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://ko-fi.com/castdrian"] options:@{} completionHandler:nil];
    } else if (indexPath.section == DeArrowSettingsSectionFiltering && indexPath.row == DeArrowFilteringRowTitle) {
        [self presentTitlePickerFromCell:[tableView cellForRowAtIndexPath:indexPath]];
    } else if (indexPath.section == DeArrowSettingsSectionCache) {
        [[DeArrowPreferences sharedPreferences] clearCache];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:DeArrowLocalized(@"CACHE_CLEARED", @"Cache cleared")
                                                                         message:nil
                                                                  preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:DeArrowLocalized(@"OK", @"OK") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else if (indexPath.section == DeArrowSettingsSectionAbout && indexPath.row == 1) {
        [self openChangelog];
    } else if (indexPath.section == DeArrowSettingsSectionAbout && indexPath.row == 2) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/castdrian/DeArrow"] options:@{} completionHandler:nil];
    }
}

@end

UIViewController *CreateDeArrowSettingsViewController(void) {
    return [DeArrowSettingsViewController new];
}
