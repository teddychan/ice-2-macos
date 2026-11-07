//
//  MenuBarAgentBridge.m
//  Ice
//

#import "MenuBarAgentBridge.h"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>
#import <objc/message.h>

// Runtime selectors and AX tree shape verified by our standalone prototype on
// 27.0 (26A428). Research: https://github.com/fif7y/pelmet (GPL-3.0).
BOOL ICEMenuBarAgentAvailable(void) {
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

void ICEMenuBarAgentInvalidate(id assertion) {
    @try {
        SEL selector = NSSelectorFromString(@"invalidate");
        if ([assertion respondsToSelector:selector]) {
            ((void (*)(id, SEL))objc_msgSend)(assertion, selector);
        }
    } @catch (NSException *exception) {
        NSLog(@"Ice native menu bar invalidation failed: %@", exception.reason);
    }
}

id ICEMenuBarAgentActivate(NSArray<NSNumber *> *systemItems, NSArray<NSString *> *bundles,
                          void (^completion)(NSError *)) {
    if (!ICEMenuBarAgentAvailable()) return nil;
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
        ICEMenuBarAgentInvalidate(assertion);
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

/// Adds the names of the SystemUIServer extras at or below `element` to `extras`.
/// MenuBarAgent hosts an extra either directly (the extra's own element) or, on some
/// displays, as SystemUIServer's application → menu bar → extra, so an element without
/// a description is searched; only a leaf without one is an extra that has no name.
static void ICECollectSystemUIExtras(AXUIElementRef element, NSUInteger depth,
                                     NSMutableArray<NSString *> *extras, BOOL *unnamed) {
    id extra = ICEAttribute(element, kAXDescriptionAttribute);
    if ([extra isKindOfClass:NSString.class] && [extra length]) {
        // Descriptions are not consistently capitalized ("eject", "VPN").
        NSString *label = [[extra substringToIndex:1].localizedUppercaseString
            stringByAppendingString:[extra substringFromIndex:1]];
        if (![extras containsObject:label]) [extras addObject:label];
        return;
    }
    NSArray *children = depth < 3 ? ICEChildren(element) : @[];
    if (children.count == 0) {
        *unnamed = YES;
        return;
    }
    for (id child in children) {
        ICECollectSystemUIExtras((__bridge AXUIElementRef)child, depth + 1, extras, unnamed);
    }
}

static void ICECollect(AXUIElementRef element, pid_t agentPID, NSUInteger depth,
                       NSMutableDictionary<NSString *, NSDictionary *> *items, NSUInteger *budget) {
    if (depth > 4 || *budget == 0) return;
    (*budget)--;
    pid_t pid = 0;
    if (AXUIElementGetPid(element, &pid) == kAXErrorSuccess && pid > 0 && pid != agentPID) {
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        NSString *bundle = app.bundleIdentifier;
        if (bundle) {
            NSString *name = app.localizedName ?: bundle;
            // SystemUIServer hosts several unrelated extras (VPN, …): name the item after
            // the extras it shows, joined, since they can only be hidden together.
            if ([bundle isEqualToString:@"com.apple.systemuiserver"]) {
                // Only an extra's description names it; the process element's title is just
                // "SystemUIServer". Each display repeats the extras, so skip known names.
                // Some extras (Time Machine) have no description at all; they still move with
                // the item, so the name gets a trailing "…" rather than leaving them out.
                NSMutableArray<NSString *> *extras = [items[bundle][@"extras"] mutableCopy] ?: [NSMutableArray array];
                BOOL unnamed = [items[bundle][@"unnamed"] boolValue];
                ICECollectSystemUIExtras(element, 0, extras, &unnamed);
                if (extras.count) {
                    name = [extras componentsJoinedByString:@", "];
                    if (unnamed) name = [name stringByAppendingString:@", …"];
                }
                items[bundle] = @{@"bundle": bundle, @"name": name, @"extras": extras, @"unnamed": @(unnamed)};
                return;
            }
            items[bundle] = @{@"bundle": bundle, @"name": name};
            return;
        }
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

NSArray<NSDictionary<NSString *, NSString *> *> *ICEMenuBarAgentSnapshot(void) {
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
    // Rows are typed as string dictionaries: drop the non-string bookkeeping keys
    // ICECollect keeps while it merges SystemUIServer's extras.
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:items.count];
    for (NSDictionary *row in items.allValues) {
        NSMutableDictionary *clean = [row mutableCopy];
        [clean removeObjectsForKeys:@[@"extras", @"unnamed"]];
        [rows addObject:clean];
    }
    return rows;
}

BOOL ICEMenuBarAgentElementHasIdentifier(CGPoint point, NSString *identifier) {
    AXUIElementRef systemWide = AXUIElementCreateSystemWide();
    AXUIElementRef element = NULL;
    AXError error = AXUIElementCopyElementAtPosition(systemWide, point.x, point.y, &element);
    CFRelease(systemWide);
    if (error != kAXErrorSuccess || !element) return NO;
    // A click can land on the item itself or on the padding of the group that holds it.
    BOOL found = [ICEAttribute(element, kAXIdentifierAttribute) isEqual:identifier];
    for (id child in found ? @[] : ICEChildren(element)) {
        if ([ICEAttribute((__bridge AXUIElementRef)child, kAXIdentifierAttribute) isEqual:identifier]) {
            found = YES;
            break;
        }
    }
    CFRelease(element);
    return found;
}

static AXUIElementRef ICEFindItem(AXUIElementRef element, pid_t agentPID, NSString *bundle,
                                  NSArray<NSString *> *identifiers, NSUInteger depth, NSUInteger *budget) {
    if (depth > 4 || *budget == 0) return NULL;
    (*budget)--;
    pid_t pid = 0;
    if (AXUIElementGetPid(element, &pid) == kAXErrorSuccess && pid > 0 && pid != agentPID) {
        NSString *owner = [NSRunningApplication runningApplicationWithProcessIdentifier:pid].bundleIdentifier;
        return bundle && [owner isEqualToString:bundle] ? (AXUIElementRef)CFRetain(element) : NULL;
    }
    id identifier = ICEAttribute(element, kAXIdentifierAttribute);
    if ([identifier isKindOfClass:NSString.class] && [identifiers containsObject:identifier]) {
        return (AXUIElementRef)CFRetain(element);
    }
    for (id child in ICEChildren(element)) {
        AXUIElementRef found = ICEFindItem((__bridge AXUIElementRef)child, agentPID, bundle, identifiers, depth + 1, budget);
        if (found) return found;
    }
    return NULL;
}

pid_t ICEMenuBarAgentPress(NSString *bundle, NSArray<NSString *> *identifiers) {
    if (!AXIsProcessTrusted()) return 0;
    NSRunningApplication *agent = [NSRunningApplication
        runningApplicationsWithBundleIdentifier:@"com.apple.MenuBarAgent"].firstObject;
    if (!agent) return 0;
    AXUIElementRef root = AXUIElementCreateApplication(agent.processIdentifier);
    AXUIElementSetMessagingTimeout(root, 0.1);
    AXUIElementRef item = NULL;
    NSUInteger budget = 256;
    for (id window in ICEChildren(root)) {
        item = ICEFindItem((__bridge AXUIElementRef)window, agent.processIdentifier, bundle, identifiers, 0, &budget);
        if (item) break;
    }
    CFRelease(root);
    if (!item) return 0;
    pid_t pid = 0;
    AXUIElementGetPid(item, &pid);
    // The owning app runs its menu inside the press handler, so the call only returns once
    // the menu closes, as kAXErrorCannotComplete after the timeout. The menu is open either way.
    AXUIElementSetMessagingTimeout(item, 0.25);
    AXUIElementPerformAction(item, kAXPressAction);
    CFRelease(item);
    return pid;
}
