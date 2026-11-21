import Foundation

public struct Usage: Codable, Sendable, Equatable {
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

public struct ChatCompletionResponse: Decodable, Sendable {
    public struct Choice: Decodable, Sendable {
        public struct Message: Decodable, Sendable {
            public let role: String?
            public let content: String?
        }

        public let index: Int?
        public let message: Message
        public let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }

    public let id: String?
    public let model: String?
    public let choices: [Choice]
    public let usage: Usage?
}

public struct ProofreadingChange: Codable, Sendable, Equatable {
    public let before: String
    public let after: String
    public let reason: String

    public init(before: String, after: String, reason: String) {
        self.before = before
        self.after = after
        self.reason = reason
    }
}

public struct ProofreadingMetadata: Codable, Sendable, Equatable {
    public let model: String
    public let usage: Usage?
    public let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case model, usage
        case finishReason = "finish_reason"
    }
}

public struct ProofreadingResult: Codable, Sendable, Equatable {
    public let correctedText: String
    public let changes: [ProofreadingChange]
    public let comments: String
    public let metadata: ProofreadingMetadata

    enum CodingKeys: String, CodingKey {
        case correctedText = "corrected_text"
        case changes, comments, metadata
    }

    public init(
        correctedText: String,
        changes: [ProofreadingChange],
        comments: String,
        metadata: ProofreadingMetadata
    ) {
        self.correctedText = correctedText
        self.changes = changes
        self.comments = comments
        self.metadata = metadata
    }
}

struct StructuredProofreadingResult: Decodable {
    let correctedText: String
    let changes: [ProofreadingChange]
    let comments: String

    enum CodingKeys: String, CodingKey {
        case correctedText = "corrected_text"
        case changes, comments
    }
}
