import Foundation
#if os(Windows)
import WinSDK
#endif

public enum CredentialSource: String, Sendable {
    case environment
    case secureStore = "secure_store"
    case none
}

public enum CredentialStore {
    public static var credentialURL: URL {
        if let override = ProcessInfo.processInfo.environment["SARASHINA_CREDENTIAL_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        #if os(Windows)
        let root = ProcessInfo.processInfo.environment["APPDATA"]
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        #else
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config").path
        #endif
        return URL(fileURLWithPath: root)
            .appendingPathComponent("sarashina-cli", isDirectory: true)
            .appendingPathComponent("credential.dpapi")
    }

    public static func source() -> CredentialSource {
        if let key = ProcessInfo.processInfo.environment["SARASHINA_API_KEY"], !key.isEmpty {
            return .environment
        }
        return FileManager.default.fileExists(atPath: credentialURL.path) ? .secureStore : .none
    }

    public static func resolveAPIKey() throws -> String {
        if let key = ProcessInfo.processInfo.environment["SARASHINA_API_KEY"], !key.isEmpty {
            return key
        }
        guard FileManager.default.fileExists(atPath: credentialURL.path) else {
            throw SarashinaError.missingAPIKey
        }

        #if os(Windows)
        let encrypted = try Data(contentsOf: credentialURL)
        let decrypted = try unprotect(encrypted)
        guard let key = String(data: decrypted, encoding: .utf8), !key.isEmpty else {
            throw SarashinaError(code: "credential_store_error", message: "The stored API key is invalid")
        }
        return key
        #else
        throw SarashinaError(
            code: "unsupported_secure_store",
            message: "Secure credential storage is currently implemented for Windows. Set SARASHINA_API_KEY on this platform."
        )
        #endif
    }

    public static func set(apiKey: String) throws {
        guard !apiKey.isEmpty else {
            throw SarashinaError(code: "empty_api_key", message: "API key cannot be empty")
        }
        #if os(Windows)
        let encrypted = try protect(Data(apiKey.utf8))
        let directory = credentialURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encrypted.write(to: credentialURL, options: .atomic)
        #else
        throw SarashinaError(
            code: "unsupported_secure_store",
            message: "Secure credential storage is currently implemented for Windows."
        )
        #endif
    }

    public static func delete() throws -> Bool {
        guard FileManager.default.fileExists(atPath: credentialURL.path) else { return false }
        try FileManager.default.removeItem(at: credentialURL)
        return true
    }

    #if os(Windows)
    private static func protect(_ data: Data) throws -> Data {
        try transform(data) { input, output in
            CryptProtectData(
                &input,
                nil,
                nil,
                nil,
                nil,
                DWORD(CRYPTPROTECT_UI_FORBIDDEN),
                &output
            )
        }
    }

    private static func unprotect(_ data: Data) throws -> Data {
        try transform(data) { input, output in
            CryptUnprotectData(
                &input,
                nil,
                nil,
                nil,
                nil,
                DWORD(CRYPTPROTECT_UI_FORBIDDEN),
                &output
            )
        }
    }

    private static func transform(
        _ data: Data,
        operation: (inout DATA_BLOB, inout DATA_BLOB) -> Bool
    ) throws -> Data {
        try data.withUnsafeBytes { rawBuffer in
            var input = DATA_BLOB(
                cbData: DWORD(rawBuffer.count),
                pbData: UnsafeMutablePointer<BYTE>(mutating: rawBuffer.bindMemory(to: BYTE.self).baseAddress)
            )
            var output = DATA_BLOB()
            guard operation(&input, &output), let bytes = output.pbData else {
                throw SarashinaError(
                    code: "credential_store_error",
                    message: "Windows DPAPI operation failed (error \(GetLastError()))"
                )
            }
            defer { LocalFree(HLOCAL(bytes)) }
            return Data(bytes: bytes, count: Int(output.cbData))
        }
    }
    #endif
}
