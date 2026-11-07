//
//  MenuBarAgentBridge.h
//  Ice
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN
BOOL ICEMenuBarAgentAvailable(void);
id _Nullable ICEMenuBarAgentActivate(NSArray<NSNumber *> *systemItems,
                                    NSArray<NSString *> *bundles,
                                    void (^completion)(NSError * _Nullable));
void ICEMenuBarAgentInvalidate(id _Nullable assertion);
NSArray<NSDictionary<NSString *, NSString *> *> *ICEMenuBarAgentSnapshot(void);
/// Presses the menu bar item that belongs to `bundle` (an app) or carries one of `identifiers`
/// (a system item), which opens its menu. Returns the pressed element's process id, or 0 when
/// no such item is on screen.
pid_t ICEMenuBarAgentPress(NSString * _Nullable bundle, NSArray<NSString *> *identifiers);
/// Whether the accessibility element at `point` (or one of its children) has `identifier`.
BOOL ICEMenuBarAgentElementHasIdentifier(CGPoint point, NSString *identifier);
NS_ASSUME_NONNULL_END
