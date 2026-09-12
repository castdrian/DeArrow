#import "SettingsViewController.h"

#import "Preferences.h"

typedef NS_ENUM(NSInteger, DeArrowSettingsRow) {
    DeArrowSettingsRowEnabled = 0,
    DeArrowSettingsRowTitle,
    DeArrowSettingsRowThumbnails,
    DeArrowSettingsRowClearCache,
    DeArrowSettingsRowDonate,
    DeArrowSettingsRowVersion
};

@interface DeArrowSettingsViewController : UITableViewController
@property(nonatomic, strong) UISwitch *enabledSwitch;
@property(nonatomic, strong) UISwitch *thumbnailSwitch;
@end

@implementation DeArrowSettingsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = @"DeArrow";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.rowHeight = 52.0;
    self.tableView.tableFooterView = [UIView new];
    self.enabledSwitch = [UISwitch new];
    self.thumbnailSwitch = [UISwitch new];
    [self.enabledSwitch addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];
    [self.thumbnailSwitch addTarget:self action:@selector(thumbnailsChanged:) forControlEvents:UIControlEventValueChanged];
    [self refreshControls];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
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
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0)
        return 3;
    if (section == 1)
        return 2;
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0)
        return @"DeArrow";
    if (section == 1)
        return @"Cache";
    return @"About";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"DeArrowSettingsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    if (indexPath.section == 0 && indexPath.row == DeArrowSettingsRowEnabled) {
        cell.textLabel.text = @"Enable DeArrow";
        cell.accessoryView = self.enabledSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 0 && indexPath.row == DeArrowSettingsRowTitle) {
        cell.textLabel.text = @"Preferred title";
        cell.detailTextLabel.text = [DeArrowPreferences sharedPreferences].titlePreference == DeArrowTitlePreferenceOriginal ? @"Original" : @"DeArrow";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 0 && indexPath.row == DeArrowSettingsRowThumbnails) {
        cell.textLabel.text = @"Replace thumbnails";
        cell.accessoryView = self.thumbnailSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 1 && indexPath.row == 0) {
        cell.textLabel.text = @"Clear cache";
    } else if (indexPath.section == 1 && indexPath.row == 1) {
        cell.textLabel.text = @"Donate";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 2 && indexPath.row == 0) {
        cell.textLabel.text = @"Version";
        cell.detailTextLabel.text = [DeArrowPreferences sharedPreferences].installedVersion;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        cell.textLabel.text = @"DeArrow on GitHub";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == DeArrowSettingsRowTitle) {
        UIAlertController *controller = [UIAlertController alertControllerWithTitle:@"Preferred title"
                                                                               message:nil
                                                                        preferredStyle:UIAlertControllerStyleActionSheet];
        __weak typeof(self) weakSelf = self;
        [controller addAction:[UIAlertAction actionWithTitle:@"DeArrow" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [DeArrowPreferences sharedPreferences].titlePreference = DeArrowTitlePreferenceDeArrow;
            [weakSelf refreshControls];
        }]];
        [controller addAction:[UIAlertAction actionWithTitle:@"Original" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [DeArrowPreferences sharedPreferences].titlePreference = DeArrowTitlePreferenceOriginal;
            [weakSelf refreshControls];
        }]];
        [controller addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        if (controller.popoverPresentationController) {
            UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
            controller.popoverPresentationController.sourceView = cell;
            controller.popoverPresentationController.sourceRect = cell.bounds;
        }
        [self presentViewController:controller animated:YES completion:nil];
    } else if (indexPath.section == 1 && indexPath.row == 0) {
        [[DeArrowPreferences sharedPreferences] clearCache];
        UIAlertController *controller = [UIAlertController alertControllerWithTitle:@"Cache cleared"
                                                                               message:nil
                                                                        preferredStyle:UIAlertControllerStyleAlert];
        [controller addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:controller animated:YES completion:nil];
    } else if (indexPath.section == 1 && indexPath.row == 1) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://ko-fi.com/castdrian"] options:@{} completionHandler:nil];
    } else if (indexPath.section == 2 && indexPath.row == 1) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/castdrian/DeArrow"] options:@{} completionHandler:nil];
    }
}

@end

UIViewController *CreateDeArrowSettingsViewController(void) {
    return [DeArrowSettingsViewController new];
}
