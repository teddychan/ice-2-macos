//
//  NativeMenuBarBridge.m
//  Ice
//

#import "NativeMenuBarBridge.h"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>
#import <objc/message.h>

// Runtime selectors and AX tree shape verified by our standalone prototype on
// 27.0 (26A428). Research: https://github.com/fif7y/pelmet (GPL-3.0).
BOOL ICENativeMenuBarAvailable(void) {
    static void *framework;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        framework = dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_LAZY);
    });
    Class config = NSClassFromString(@"MBAssessmentModeConfiguration");
    Class assertion = NSClassFromString(@"MBAssessmentModeAssertion");
    return framework &&
        [config instancesRespondToSelector:NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:")] &&
        [assertion instancesRespondToSelector:NSSelectorFromString(@"activateWithConfiguration:completionHandler:")] &&
        [assertion instancesRespondToSelector:NSSelectorFromString(@"invalidate")];
}

void ICENativeMenuBarInvalidate(id assertion) {
    @try {
        SEL selector = NSSelectorFromString(@"invalidate");
        if ([assertion respondsToSelector:selector]) {
            ((void (*)(id, SEL))objc_msgSend)(assertion, selector);
        }
    } @catch (NSException *exception) {
        NSLog(@"Ice native menu bar invalidation failed: %@", exception.reason);
    }
}

id ICENativeMenuBarActivate(NSArray<NSNumber *> *systemItems, NSArray<NSString *> *bundles,
                          void (^completion)(NSError *)) {
    if (!ICENativeMenuBarAvailable()) return nil;
    id assertion = nil;
    @try {
        id configuration = ((id (*)(id, SEL, id, id))objc_msgSend)(
            [NSClassFromString(@"MBAssessmentModeConfiguration") alloc],
            NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:"), systemItems, bundles);
        assertion = [[NSClassFromString(@"MBAssessmentModeAssertion") alloc] init];
        if (!configuration || !assertion) return nil;
        ((void (*)(id, SEL, id, void (^)(NSError *)))objc_msgSend)(assertion,
            NSSelectorFromString(@"activateWithConfiguration:completionHandler:"), configuration, completion);
        return assertion;
    } @catch (NSException *exception) {
        ICENativeMenuBarInvalidate(assertion);
        NSLog(@"Ice native menu bar activation failed: %@", exception.reason);
        return nil;
    }
}

static id ICEAttribute(AXUIElementRef element, CFStringRef key) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, key, &value) != kAXErrorSuccess) return nil;
    return CFBridgingRelease(value);
}

static NSArray *ICEChildren(AXUIElementRef element) {
    id value = ICEAttribute(element, kAXChildrenAttribute);
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

static void ICECollect(AXUIElementRef element, pid_t agentPID, NSUInteger depth,
                       NSMutableDictionary<NSString *, NSDictionary *> *items, NSUInteger *budget) {
    if (depth > 4 || *budget == 0) return;
    (*budget)--;
    pid_t pid = 0;
    AXUIElementGetPid(element, &pid);
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    NSString *bundle = app.bundleIdentifier;
    if (pid != agentPID && bundle) {
        items[bundle] = @{@"bundle": bundle, @"name": app.localizedName ?: bundle};
        return;
    }
    id identifier = ICEAttribute(element, kAXIdentifierAttribute);
    if ([identifier isKindOfClass:NSString.class] && [identifier hasPrefix:@"com.apple.menuextra."]) {
        id title = ICEAttribute(element, kAXTitleAttribute);
        if (![title isKindOfClass:NSString.class] || ![title length]) {
            title = ICEAttribute(element, kAXDescriptionAttribute);
        }
        items[identifier] = @{@"identifier": identifier,
                             @"name": [title isKindOfClass:NSString.class] ? title : identifier};
        return;
    }
    for (id child in ICEChildren(element)) {
        ICECollect((__bridge AXUIElementRef)child, agentPID, depth + 1, items, budget);
    }
}

NSArray<NSDictionary<NSString *, NSString *> *> *ICENativeMenuBarSnapshot(void) {
    if (!AXIsProcessTrusted()) return @[];
    NSRunningApplication *agent = [NSRunningApplication
        runningApplicationsWithBundleIdentifier:@"com.apple.MenuBarAgent"].firstObject;
    if (!agent) return @[];
    AXUIElementRef root = AXUIElementCreateApplication(agent.processIdentifier);
    AXUIElementSetMessagingTimeout(root, 0.1);
    NSMutableDictionary *items = [NSMutableDictionary dictionary];
    NSUInteger budget = 256;
    for (id window in ICEChildren(root)) {
        AXUIElementRef element = (__bridge AXUIElementRef)window;
        if (![ICEAttribute(element, kAXRoleAttribute) isEqual:@"AXWindow"]) continue;
        for (id group in ICEChildren(element)) {
            ICECollect((__bridge AXUIElementRef)group, agent.processIdentifier, 0, items, &budget);
        }
    }
    CFRelease(root);
    return items.allValues;
}

static void ICECollectFrames(AXUIElementRef element, NSString *identifier, NSUInteger depth,
                             NSMutableArray<NSValue *> *frames, NSUInteger *budget) {
    if (depth > 4 || *budget == 0) return;
    (*budget)--;
    id value = ICEAttribute(element, kAXIdentifierAttribute);
    if ([value isKindOfClass:NSString.class] && [value isEqualToString:identifier]) {
        CGPoint origin = CGPointZero;
        CGSize size = CGSizeZero;
        id position = ICEAttribute(element, kAXPositionAttribute);
        id extent = ICEAttribute(element, kAXSizeAttribute);
        if (position && extent &&
            AXValueGetValue((__bridge AXValueRef)position, kAXValueTypeCGPoint, &origin) &&
            AXValueGetValue((__bridge AXValueRef)extent, kAXValueTypeCGSize, &size) &&
            size.width > 0 && size.height > 0) {
            [frames addObject:[NSValue valueWithRect:NSMakeRect(origin.x, origin.y, size.width, size.height)]];
        }
        return;
    }
    // Hosted applications expose their ordinary menus too; don't enumerate them.
    if ([ICEAttribute(element, kAXRoleAttribute) isEqual:@"AXApplication"]) return;
    for (id child in ICEChildren(element)) {
        ICECollectFrames((__bridge AXUIElementRef)child, identifier, depth + 1, frames, budget);
    }
}

NSArray<NSValue *> *ICENativeMenuBarFrames(NSString *identifier) {
    if (!AXIsProcessTrusted()) return @[];
    NSRunningApplication *agent = [NSRunningApplication
        runningApplicationsWithBundleIdentifier:@"com.apple.MenuBarAgent"].firstObject;
    if (!agent) return @[];
    AXUIElementRef root = AXUIElementCreateApplication(agent.processIdentifier);
    AXUIElementSetMessagingTimeout(root, 0.1);
    NSMutableArray<NSValue *> *frames = [NSMutableArray array];
    NSUInteger budget = 256;
    for (id window in ICEChildren(root)) {
        AXUIElementRef element = (__bridge AXUIElementRef)window;
        if (![ICEAttribute(element, kAXRoleAttribute) isEqual:@"AXWindow"]) continue;
        for (id group in ICEChildren(element)) {
            ICECollectFrames((__bridge AXUIElementRef)group, identifier, 0, frames, &budget);
        }
    }
    CFRelease(root);
    return frames;
}
