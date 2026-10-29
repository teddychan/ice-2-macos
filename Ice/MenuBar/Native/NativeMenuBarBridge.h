//
//  NativeMenuBarBridge.h
//  Ice
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
BOOL ICENativeMenuBarAvailable(void);
id _Nullable ICENativeMenuBarActivate(NSArray<NSNumber *> *systemItems,
                                    NSArray<NSString *> *bundles,
                                    void (^completion)(NSError * _Nullable));
void ICENativeMenuBarInvalidate(id _Nullable assertion);
NSArray<NSDictionary<NSString *, NSString *> *> *ICENativeMenuBarSnapshot(void);
/// Screen frames (global, top-left origin) of every copy of a native system item,
/// e.g. `com.apple.menuextra.clock`, one per display. Empty when unavailable.
NSArray<NSValue *> *ICENativeMenuBarFrames(NSString *identifier);
NS_ASSUME_NONNULL_END
