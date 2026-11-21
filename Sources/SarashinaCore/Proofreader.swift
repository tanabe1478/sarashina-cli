import Foundation

public struct ProofreadingOptions: Sendable {
    public var model: String
    public var style: String
    public var focus: String?
    public var reasoningEffort: String
    public var maxCompletionTokens: Int

    public init(
        model: String = "sarashina3.2-mini-thinking",
        style: String = "preserve",
        focus: String? = nil,
        reasoningEffort: String = "low",
        maxCompletionTokens: Int = 4_000
    ) {
        self.model = model
        self.style = style
        self.focus = focus
        self.reasoningEffort = reasoningEffort
        self.maxCompletionTokens = maxCompletionTokens
    }
}

public struct Proofreader: Sendable {
    private let client: SarashinaClient

    public init(client: SarashinaClient) {
        self.client = client
    }

    public func proofread(_ text: String, options: ProofreadingOptions = .init()) async throws -> ProofreadingResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProofreadingError.emptyInput
        }

        let styleInstruction: String
        switch options.style {
        case "preserve": styleInstruction = "原文の文体（常体・敬体・語調）をできる限り維持してください。"
        case "polite": styleInstruction = "自然な敬体（です・ます調）に統一してください。"
        case "plain": styleInstruction = "自然な常体（だ・である調）に統一してください。"
        default: throw ProofreadingError.unknownStyle(options.style)
        }

        var systemLines = [
            "あなたは日本語文章の校正・推敲を行う専門家です。",
            "原文の意味、事実関係、固有名詞を勝手に変更しないでください。",
            "誤字脱字、文法、助詞、表記ゆれ、不自然な表現、冗長さを確認してください。",
            styleInstruction,
            "修正が不要な場合は corrected_text に原文をそのまま入れ、changes を空配列にしてください。"
        ]
        if let focus = options.focus { systemLines.append("特に次の観点を重視してください: \(focus)") }

        var payload: [String: Any] = [
            "model": options.model,
            "messages": [
                ["role": "system", "content": systemLines.joined(separator: "\n")],
                ["role": "user", "content": "次の文章を添削してください。\n\n\(text)"]
            ],
            "temperature": 0.2,
            "max_completion_tokens": options.maxCompletionTokens,
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "proofreading_result",
                    "strict": true,
                    "schema": Self.resultSchema
                ]
            ]
        ]
        if options.model.contains("thinking") {
            payload["reasoning_effort"] = options.reasoningEffort
        }

        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let response = try await client.createChatCompletion(payload: payloadData)
        guard let choice = response.choices.first, let content = choice.message.content else {
            throw ProofreadingError.missingContent
        }

        let normalized = content
            .replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
        guard let data = normalized.data(using: .utf8),
              let structured = try? JSONDecoder().decode(StructuredProofreadingResult.self, from: data) else {
            throw ProofreadingError.invalidStructuredOutput
        }

        return ProofreadingResult(
            correctedText: structured.correctedText,
            changes: structured.changes,
            comments: structured.comments,
            metadata: ProofreadingMetadata(
                model: response.model ?? options.model,
                usage: response.usage,
                finishReason: choice.finishReason
            )
        )
    }

    private static var resultSchema: [String: Any] { [
        "type": "object",
        "properties": [
            "corrected_text": ["type": "string"],
            "changes": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "before": ["type": "string"],
                        "after": ["type": "string"],
                        "reason": ["type": "string"]
                    ],
                    "required": ["before", "after", "reason"],
                    "additionalProperties": false
                ]
            ],
            "comments": ["type": "string"]
        ],
        "required": ["corrected_text", "changes", "comments"],
        "additionalProperties": false
    ] }
}
