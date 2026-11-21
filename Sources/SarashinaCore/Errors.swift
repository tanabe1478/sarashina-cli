import Foundation

public struct SarashinaError: Error, LocalizedError, Sendable {
    public let code: String
    public let message: String
    public let status: Int?
    public let retryable: Bool
    public let retryAfterMilliseconds: UInt64?

    public init(
        code: String,
        message: String,
        status: Int? = nil,
        retryable: Bool = false,
        retryAfterMilliseconds: UInt64? = nil
    ) {
        self.code = code
        self.message = message
        self.status = status
        self.retryable = retryable
        self.retryAfterMilliseconds = retryAfterMilliseconds
    }

    public var errorDescription: String? { message }

    public static let missingAPIKey = SarashinaError(
        code: "missing_api_key",
        message: "No API key is configured. Run `sarashina auth set` or set SARASHINA_API_KEY."
    )
}

public enum ProofreadingError: Error, LocalizedError, Sendable {
    case emptyInput
    case unknownStyle(String)
    case missingContent
    case invalidStructuredOutput

    public var errorDescription: String? {
        switch self {
        case .emptyInput: "Input text is empty"
        case .unknownStyle(let style): "Unknown style: \(style)"
        case .missingContent: "Sarashina response did not contain message content"
        case .invalidStructuredOutput: "Sarashina returned invalid structured output"
        }
    }
}
