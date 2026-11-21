import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import SarashinaCore

private actor MockTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    let handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    init(handler: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return try handler(request)
    }

    func lastRequest() -> URLRequest? { requests.last }
}

private func response(status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.sarashina.ai/v1/chat/completions")!,
        statusCode: status,
        httpVersion: nil,
        headerFields: headers
    )!
}

@Test func sendsBearerAuthenticatedRequest() async throws {
    let data = Data(#"{"choices":[]}"#.utf8)
    let transport = MockTransport { _ in (data, response(status: 200)) }
    let client = SarashinaClient(apiKey: "secret", maxRetries: 0, transport: transport)

    _ = try await client.createChatCompletion(payload: Data("{}".utf8))

    let request = await transport.lastRequest()
    #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    #expect(request?.url?.absoluteString == "https://api.sarashina.ai/v1/chat/completions")
}

@Test func mapsUnauthorizedResponse() async {
    let data = Data(#"{"message":"Unauthorized"}"#.utf8)
    let transport = MockTransport { _ in (data, response(status: 401)) }
    let client = SarashinaClient(apiKey: "bad", maxRetries: 0, transport: transport)

    do {
        _ = try await client.createChatCompletion(payload: Data("{}".utf8))
        Issue.record("Expected an error")
    } catch let error as SarashinaError {
        #expect(error.code == "unauthorized")
        #expect(error.status == 401)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func decodesStructuredProofreadingResult() async throws {
    let content = #"{"corrected_text":"昨日は会議で話をしました。","changes":[{"before":"話しを","after":"話を","reason":"送り仮名"}],"comments":"修正しました。"}"#
    let body: [String: Any] = [
        "model": "sarashina3.2-mini-thinking",
        "choices": [[
            "index": 0,
            "message": ["role": "assistant", "content": content],
            "finish_reason": "stop"
        ]]
    ]
    let data = try JSONSerialization.data(withJSONObject: body)
    let transport = MockTransport { _ in (data, response(status: 200)) }
    let client = SarashinaClient(apiKey: "secret", maxRetries: 0, transport: transport)

    let result = try await Proofreader(client: client).proofread("昨日は会議で話しをしました。")

    #expect(result.correctedText == "昨日は会議で話をしました。")
    #expect(result.changes.count == 1)
    #expect(result.metadata.finishReason == "stop")
}

@Test func omitsReasoningEffortForNonThinkingModel() async throws {
    let content = #"{"corrected_text":"文章","changes":[],"comments":""}"#
    let body: [String: Any] = [
        "choices": [["message": ["content": content], "finish_reason": "stop"]]
    ]
    let data = try JSONSerialization.data(withJSONObject: body)
    let transport = MockTransport { _ in (data, response(status: 200)) }
    let client = SarashinaClient(apiKey: "secret", maxRetries: 0, transport: transport)

    _ = try await Proofreader(client: client).proofread("文章", options: .init(model: "sarashina3-nano"))

    let request = await transport.lastRequest()
    let payload = try #require(request?.httpBody)
    let object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
    #expect(object["reasoning_effort"] == nil)
}
