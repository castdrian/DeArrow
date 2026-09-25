#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "ImageSetterSupport.h"

@interface                       TestImageNode : NSObject
@property (nonatomic, strong) id image;
@property (nonatomic, strong) id resetImage;
@property (nonatomic) NSUInteger setterCalls;
@property (nonatomic) NSUInteger visibleStateCalls;
- (void)didEnterVisibleState;
@end

@implementation TestImageNode

- (void)setImage:(id)image
{
    self.setterCalls++;
    _image = image;
}

- (void)didEnterVisibleState
{
    self.visibleStateCalls++;
    _image = self.resetImage;
}

@end

int main(void)
{
    TestImageNode *node        = [TestImageNode new];
    id             sourceImage = [NSObject new];
    id             replacement = [NSObject new];
    IMP original = class_getMethodImplementation(TestImageNode.class, @selector(setImage:));

    DeArrowInvokeImageSetterWithReplacement(node, @selector(setImage:), original, sourceImage,
                                            replacement);
    if (node.image != replacement || node.setterCalls != 2)
        return 1;

    node.setterCalls = 0;
    DeArrowInvokeImageSetterWithReplacement(node, @selector(setImage:), original, sourceImage, nil);
    if (node.image != sourceImage || node.setterCalls != 1)
        return 1;

    node.setterCalls = 0;
    DeArrowInvokeImageSetterWithReplacement(node, @selector(setImage:), original, replacement,
                                            replacement);
    if (node.image != replacement || node.setterCalls != 1)
        return 1;

    IMP visibleStateOriginal =
        class_getMethodImplementation(TestImageNode.class, @selector(didEnterVisibleState));
    node.resetImage  = sourceImage;
    node.setterCalls = 0;
    for (NSUInteger index = 0; index < 20; index++)
    {
        DeArrowInvokeVisibleStateWithReplacement(
            node, @selector(didEnterVisibleState), visibleStateOriginal,
            ^id(__unused id object) { return replacement; },
            ^(id object, id image) { [object setImage:image]; });
        if (node.image != replacement || node.visibleStateCalls != index + 1 ||
            node.setterCalls != index + 1)
            return 1;
    }

    puts("image setter replacement forwarding passed");
    return 0;
}
