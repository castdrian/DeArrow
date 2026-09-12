#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ASDisplayNode : NSObject
@property(nonatomic, weak) ASDisplayNode *yogaParent;
- (void)addSubnode:(id)subnode;
- (void)insertYogaChild:(id)child atIndex:(NSUInteger)index;
@end

@interface ELMCellNode : ASDisplayNode
@property(nonatomic, strong) id element;
@end

@interface ASImageNode : ASDisplayNode
@property(nonatomic, strong) UIImage *image;
@end

@interface ELMImageNode : ASImageNode
- (void)imageNode:(id)node didLoadImage:(UIImage *)image;
@end

@interface ASTextNode : ASDisplayNode
@property(nonatomic, copy) NSAttributedString *attributedText;
@end

@interface ELMTextNode : ASTextNode
@property(nonatomic, strong) id element;
@end

@interface YTFormattedStringLabel : UILabel
@end

@interface YTThumbnailController : NSObject
- (instancetype)initWithImageView:(id)imageView URLs:(NSDictionary *)URLs imageService:(id)imageService;
@end

@interface YTImageView : UIView
@property(nonatomic, weak) id delegate;
- (void)setImage:(UIImage *)image animated:(BOOL)animated;
@end

@interface YTSettingsCell : UITableViewCell
@end

@interface YTIIcon : NSObject
@property(nonatomic) NSInteger iconType;
@end

@interface YTSettingsSectionItem : NSObject
+ (instancetype)itemWithTitle:(NSString *)title
             titleDescription:(NSString *)titleDescription
      accessibilityIdentifier:(NSString *)accessibilityIdentifier
              detailTextBlock:(NSString *(^)(void))detailTextBlock
                  selectBlock:(BOOL (^)(YTSettingsCell *, NSUInteger))selectBlock;
+ (instancetype)itemWithTitle:(NSString *)title
             titleDescription:(NSString *)titleDescription
      accessibilityIdentifier:(NSString *)accessibilityIdentifier
              detailTextBlock:(NSString *(^)(void))detailTextBlock
                  selectBlock:(BOOL (^)(YTSettingsCell *, NSUInteger))selectBlock
                 settingItemId:(NSUInteger)settingItemId;
@end

@interface YTSettingsSectionItemManager : NSObject
- (id)parentResponder;
- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry;
@end

@interface YTSettingsGroupData : NSObject
@property(nonatomic, readonly) NSUInteger type;
- (instancetype)initWithGroupType:(NSUInteger)groupType;
- (NSArray<NSNumber *> *)orderedCategories;
- (NSArray<NSNumber *> *)orderedCategoriesForGroupType:(NSUInteger)type;
- (NSString *)titleForSettingGroupType:(NSUInteger)type;
+ (NSMutableArray<NSNumber *> *)tweaks;
@end

@interface YTSettingsViewController : UIViewController
- (void)setSectionItems:(NSMutableArray *)items
            forCategory:(NSInteger)category
                  title:(NSString *)title
                  icon:(YTIIcon *)icon
       titleDescription:(NSString *)titleDescription
           headerHidden:(BOOL)headerHidden;
- (void)setSectionItems:(NSMutableArray *)items
            forCategory:(NSInteger)category
                  title:(NSString *)title
       titleDescription:(NSString *)titleDescription
           headerHidden:(BOOL)headerHidden;
- (void)sendSettingsNavigationEndpointForCategory:(NSUInteger)category;
- (void)didReceiveDrillDownItem:(id)item;
- (void)pushViewController:(UIViewController *)viewController;
- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated;
- (void)showOrPushViewController:(UIViewController *)viewController;
- (void)showViewController:(UIViewController *)viewController sender:(id)sender;
- (void)reloadData;
@end

@interface YTAppSettingsGroupPresentationData : NSObject
+ (NSArray<YTSettingsGroupData *> *)orderedGroups;
@end

@interface YTPlayerViewController : UIViewController
- (NSString *)currentVideoID;
- (NSString *)contentVideoID;
@end

@interface YTReelPlayerViewController : UIViewController
- (id)currentVideo;
- (NSString *)videoId;
@end

@interface UIView (DeArrowPrivateController)
- (UIViewController *)_viewControllerForAncestor;
@end
