#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "HookSupport.h"

static __strong id lastOriginalPayload;
static __strong id lastHookPayload;
static SEL lastOriginalSelector;

static void StorePayload(id object, SEL selector, id payload)
{
    lastOriginalSelector = selector;
    lastOriginalPayload  = payload;
}

@interface HookABIObject : NSObject
- (void)storePayload:(id)payload;
@end

@implementation HookABIObject
- (void)storePayload:(id)payload
{
    StorePayload(self, _cmd, payload);
}
@end

int main(void)
{
    SEL selector = @selector(storePayload:);
    BOOL installed = DeArrowInstallInstanceHook(
        HookABIObject.class, selector, ^id(IMP original, SEL command) {
            return ^(id object, id payload) {
                ((void (*)(id, SEL, id)) original)(object, command, payload);
                lastHookPayload = payload;
            };
        });
    if (!installed)
        return 1;

    HookABIObject *object = [HookABIObject new];
    id expectedPayload   = [NSObject new];
    [object storePayload:expectedPayload];

    if (lastOriginalSelector != selector || lastOriginalPayload != expectedPayload ||
        lastHookPayload != expectedPayload)
        return 1;

    puts("hook block argument forwarding passed");
    return 0;
}
