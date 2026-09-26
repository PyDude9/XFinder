#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Checks if MenuBarClientCore.framework and required classes/methods are available on this macOS.
BOOL HBNativeVisibilityIsAvailable(void);

/// Activates menu bar assessment mode restriction with allowed system items and allowed bundle identifiers.
void HBNativeVisibilityActivate(NSArray<NSNumber *> *allowedSystemItems,
                                NSArray<NSString *> *allowedBundleIdentifiers,
                                void (^completion)(id _Nullable assertion, NSError * _Nullable error));

/// Invalidates a previously created assertion handle.
void HBNativeVisibilityInvalidate(id assertion);

NS_ASSUME_NONNULL_END
