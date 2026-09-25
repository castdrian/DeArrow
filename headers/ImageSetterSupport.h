#import <objc/runtime.h>

void DeArrowInvokeImageSetterWithReplacement(id object, SEL selector, IMP original, id image,
                                             id replacementImage);
void DeArrowInvokeVisibleStateWithReplacement(id object, SEL selector, IMP original,
                                              id (^replacementProvider)(id object),
                                              void (^applyReplacement)(id object, id image));
