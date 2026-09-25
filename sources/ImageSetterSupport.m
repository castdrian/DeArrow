#import "ImageSetterSupport.h"

#import <Foundation/Foundation.h>
#import <objc/message.h>

void DeArrowInvokeImageSetterWithReplacement(id object, SEL selector, IMP original, id image,
                                             id replacementImage)
{
    if (!object || !original)
        return;
    void (*invoke)(id, SEL, id) = (void (*)(id, SEL, id)) original;
    invoke(object, selector, image);
    if (replacementImage && replacementImage != image)
        invoke(object, selector, replacementImage);
}

void DeArrowInvokeVisibleStateWithReplacement(id object, SEL selector, IMP original,
                                              id (^replacementProvider)(id object),
                                              void (^applyReplacement)(id object, id image))
{
    if (!object || !original)
        return;
    ((void (*)(id, SEL)) original)(object, selector);
    if (!replacementProvider || !applyReplacement)
        return;
    id replacementImage = replacementProvider(object);
    if (!replacementImage)
        return;
    SEL imageSelector = sel_registerName("image");
    id  currentImage  = [object respondsToSelector:imageSelector]
                            ? ((id (*)(id, SEL)) objc_msgSend)(object, imageSelector)
                            : nil;
    if (currentImage != replacementImage)
        applyReplacement(object, replacementImage);
}
