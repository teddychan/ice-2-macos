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
NS_ASSUME_NONNULL_END
