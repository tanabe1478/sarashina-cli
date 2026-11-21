import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SarashinaClient: Sendable {
    public let apiKey: String
    public let baseURL: URL
    public let timeoutSeconds: TimeInterval
    public let maxRetries: Int
    private let transport: any HTTPTransport

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.sarashina.ai/v1")!,
        timeoutSeconds: TimeInterval = 60,
        maxRetries: Int = 2,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.timeoutSeconds = timeoutSeconds
        self.maxRetries = maxRetries
        self.transport = transport
    }

    public func createChatCompletion(payload: Data) async throws -> ChatCompletionResponse {
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                return try await request(payload: payload)
            } catch let error as SarashinaError {
                lastError = error
                guard error.retryable, attempt < maxRetries else { throw error }
                let fallback = UInt64(min(1 << attempt, 8)) * 1_000
                try await Task.sleep(for: .milliseconds(error.retryAfterMilliseconds ?? fallback))
            } catch {
                lastError = error
                guard attempt < maxRetries else {
                    throw SarashinaError(code: "network_error", message: error.localizedDescription, retryable: true)
                }
                try await Task.sleep(for: .milliseconds(UInt64(min(1 << attempt, 8)) * 1_000))
            }
        }

        throw lastError ?? SarashinaError(code: "api_error", message: "Request failed")
    }

    private func request(payload: Data) async throws -> ChatCompletionResponse {
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint, timeoutInterval: timeoutSeconds)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport.send(request)
        } catch let error as SarashinaError {
            throw error
        } catch {
            throw SarashinaError(code: "network_error", message: error.localizedDescription, retryable: true)
        }

        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorBody.self, from: data).message)
                ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            let retryable = [429, 500, 503].contains(response.statusCode)
            throw SarashinaError(
                code: response.statusCode == 401 ? "unauthorized" : "api_error",
                message: message,
                status: response.statusCode,
                retryable: retryable,
                retryAfterMilliseconds: retryAfter(from: response)
            )
        }

        do {
            return try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw SarashinaError(code: "invalid_response", message: "Could not decode the API response")
        }
    }

    private func retryAfter(from response: HTTPURLResponse) -> UInt64? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = Double(value) {
            return UInt64(max(0, seconds * 1_000))
        }
        return nil
    }
}

private struct APIErrorBody: Decodable {
    let message: String
}
