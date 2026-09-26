import Foundation

public protocol NativeVisibilityAssertion: AnyObject {
    func invalidate()
}

@MainActor
public protocol NativeVisibilityProviding: AnyObject {
    var isAvailable: Bool { get }
    func activate(
        allowedSystemItems: [Int],
        allowedBundleIdentifiers: [String],
        completion: @escaping @MainActor (Result<NativeVisibilityAssertion, Error>) -> Void
    )
}

@MainActor
public final class NativeVisibilityBridge: NativeVisibilityProviding {
    public init() {}

    public var isAvailable: Bool {
        return HBNativeVisibilityIsAvailable()
    }

    public func activate(
        allowedSystemItems: [Int],
        allowedBundleIdentifiers: [String],
        completion: @escaping @MainActor (Result<NativeVisibilityAssertion, Error>) -> Void
    ) {
        HBNativeVisibilityActivate(
            allowedSystemItems.map { NSNumber(value: $0) },
            allowedBundleIdentifiers
        ) { handle, error in
            Task { @MainActor in
                if let handle = handle {
                    completion(.success(Handle(raw: handle)))
                } else {
                    completion(.failure(error ?? NSError(domain: "HBNativeVisibility", code: 2)))
                }
            }
        }
    }

    private final class Handle: NativeVisibilityAssertion {
        private var raw: Any?

        init(raw: Any) {
            self.raw = raw
        }

        func invalidate() {
            guard let raw = raw else { return }
            self.raw = nil
            HBNativeVisibilityInvalidate(raw)
        }

        deinit {
            invalidate()
        }
    }
}
