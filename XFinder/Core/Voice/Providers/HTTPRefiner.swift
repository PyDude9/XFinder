import Foundation

/// A bring-your-own-key refiner speaking to any of the supported HTTP vendors.
///
/// One implementation for every vendor, because the only thing that differs between them is
/// the request/response *shape* — and that shape is decided by the pure
/// `RefinerRequestBuilder` / `RefinerResponseParser`, which the test package can assert
/// without a network. This class therefore contains no vendor-specific branches at all.
///
/// Cancellation: `URLSession.data(for:)` is cancelled by the enclosing `Task`, so pressing
/// Esc while the model is thinking aborts the HTTP request rather than letting it finish
/// and insert text the user already dismissed.
public final class HTTPRefiner: TranscriptRefiner, @unchecked Sendable {
    public let id: String

    private let kind: APIProviderKind
    private let baseURL: String
    private let model: String
    private let apiKey: String
    private let session: URLSession

    public init(kind: APIProviderKind, baseURL: String, model: String, apiKey: String) {
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.id = "http-\(kind.rawValue)"

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    public func isAvailable() async -> Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isEmpty
    }

    public func refine(_ request: RefineRequest) async throws -> String {
        guard !apiKey.isEmpty else { throw RefinerError.missingKey }
        guard let urlRequest = RefinerRequestBuilder.request(
            kind: kind,
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            messages: request.messages
        ) else {
            throw RefinerError.notConfigured
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw RefinerError.badResponse }
            guard (200...299).contains(http.statusCode) else {
                let detail = RefinerResponseParser.errorMessage(from: data)
                    ?? String(data: data, encoding: .utf8)
                    ?? ""
                throw RefinerError.http(http.statusCode, detail)
            }
            guard let text = RefinerResponseParser.text(kind: kind, from: data) else {
                throw RefinerError.badResponse
            }
            return text
        } catch let error as RefinerError {
            throw error
        } catch is CancellationError {
            throw RefinerError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw RefinerError.cancelled
        } catch {
            throw RefinerError.transport(error.localizedDescription)
        }
    }
}
