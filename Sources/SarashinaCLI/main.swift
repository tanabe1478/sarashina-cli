import Foundation
import SarashinaCore
#if os(Windows)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private let version = "0.2.0"
private let help = """
sarashina - Agent-friendly CLI for the Sarashina API (Swift)

Usage:
  sarashina auth set
  sarashina auth status [--format text|json]
  sarashina auth delete
  sarashina proofread [options] [text...]
  sarashina proofread --stdin [options]

Proofread options:
  --stdin                    Read input from stdin
  --file <path>              Read a UTF-8 file
  --format <text|json>       Output format (default: text)
  --style <preserve|polite|plain>
  --focus <instruction>      Additional proofreading focus
  --model <model>            Sarashina model ID
  --reasoning-effort <level> low, medium, or high
  --timeout <seconds>        Request timeout (default: 60)
  --max-retries <count>      Retry count (default: 2)
  -h, --help                 Show help
  -v, --version              Show version

Credentials:
  `auth set` stores the key with Windows DPAPI. SARASHINA_API_KEY takes precedence.
"""

private struct CLIError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct ProofreadArguments {
    var useStdin = false
    var file: String?
    var format = "text"
    var style = "preserve"
    var focus: String?
    var model = "sarashina3.2-mini-thinking"
    var reasoningEffort = "low"
    var timeout = 60.0
    var maxRetries = 2
    var positional: [String] = []
}

@main
struct SarashinaCommand {
    static func main() async {
        let code = await run(Array(CommandLine.arguments.dropFirst()))
        if code != 0 {
            #if os(Windows)
            ExitProcess(UInt32(code))
            #else
            exit(Int32(code))
            #endif
        }
    }

    private static func run(_ arguments: [String]) async -> Int {
        do {
            guard let command = arguments.first else {
                print(help)
                return 0
            }
            if ["-h", "--help"].contains(command) {
                print(help)
                return 0
            }
            if ["-v", "--version"].contains(command) {
                print(version)
                return 0
            }

            switch command {
            case "auth":
                return try runAuth(Array(arguments.dropFirst()))
            case "proofread":
                return try await runProofread(Array(arguments.dropFirst()))
            default:
                throw CLIError(message: "Unknown command: \(command)")
            }
        } catch {
            writeError(error, format: arguments.contains("json") ? "json" : "text")
            return exitCode(for: error)
        }
    }

    private static func runAuth(_ arguments: [String]) throws -> Int {
        guard let action = arguments.first else {
            throw CLIError(message: "Usage: sarashina auth <set|status|delete>")
        }
        switch action {
        case "set":
            let apiKey = try readSecret()
            try CredentialStore.set(apiKey: apiKey)
            print("API key stored securely.")
        case "status":
            let json = arguments.contains("--format") && arguments.last == "json"
            let source = CredentialStore.source()
            if source != .none { _ = try CredentialStore.resolveAPIKey() }
            if json {
                let configured = source != .none
                print("{\"configured\":\(configured),\"source\":\"\(source.rawValue)\"}")
            } else {
                print(source == .none ? "API key is not configured." : "API key is configured (\(source.rawValue)).")
            }
        case "delete":
            print(try CredentialStore.delete() ? "Stored API key deleted." : "No stored API key was found.")
        default:
            throw CLIError(message: "Unknown auth action: \(action)")
        }
        return 0
    }

    private static func readSecret() throws -> String {
        var value: String?
        if standardInputIsTerminal {
            FileHandle.standardError.write(Data("Sarashina API key: ".utf8))
            #if os(Windows)
            let handle = GetStdHandle(STD_INPUT_HANDLE)
            var originalMode: DWORD = 0
            guard GetConsoleMode(handle, &originalMode) else {
                throw CLIError(message: "Could not read console mode")
            }
            guard SetConsoleMode(handle, originalMode & ~DWORD(ENABLE_ECHO_INPUT)) else {
                throw CLIError(message: "Could not disable console echo")
            }
            value = readLine()
            _ = SetConsoleMode(handle, originalMode)
            FileHandle.standardError.write(Data("\n".utf8))
            #else
            value = readLine()
            #endif
        } else {
            value = readLine()
        }

        guard let value = value?.trimmingCharacters(in: .newlines), !value.isEmpty else {
            throw CLIError(message: "API key cannot be empty")
        }
        return value
    }

    private static func runProofread(_ arguments: [String]) async throws -> Int {
        let options = try parseProofreadArguments(arguments)
        let input = try readInput(options)
        let apiKey = try CredentialStore.resolveAPIKey()
        let baseURL = ProcessInfo.processInfo.environment["SARASHINA_BASE_URL"]
            .flatMap(URL.init(string:)) ?? URL(string: "https://api.sarashina.ai/v1")!
        let client = SarashinaClient(
            apiKey: apiKey,
            baseURL: baseURL,
            timeoutSeconds: options.timeout,
            maxRetries: options.maxRetries
        )
        let result = try await Proofreader(client: client).proofread(
            input,
            options: ProofreadingOptions(
                model: options.model,
                style: options.style,
                focus: options.focus,
                reasoningEffort: options.reasoningEffort
            )
        )

        if options.format == "json" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(result))
            print()
        } else {
            print(result.correctedText)
        }
        return 0
    }

    private static func parseProofreadArguments(_ arguments: [String]) throws -> ProofreadArguments {
        var result = ProofreadArguments()
        var index = 0
        func value(after option: String) throws -> String {
            guard index + 1 < arguments.count else { throw CLIError(message: "\(option) requires a value") }
            index += 1
            return arguments[index]
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--stdin": result.useStdin = true
            case "--file": result.file = try value(after: argument)
            case "--format": result.format = try value(after: argument)
            case "--style": result.style = try value(after: argument)
            case "--focus": result.focus = try value(after: argument)
            case "--model": result.model = try value(after: argument)
            case "--reasoning-effort": result.reasoningEffort = try value(after: argument)
            case "--timeout":
                guard let number = Double(try value(after: argument)), number > 0 else {
                    throw CLIError(message: "--timeout must be a positive number")
                }
                result.timeout = number
            case "--max-retries":
                guard let number = Int(try value(after: argument)), number >= 0 else {
                    throw CLIError(message: "--max-retries must be a non-negative integer")
                }
                result.maxRetries = number
            default:
                if argument.hasPrefix("-") { throw CLIError(message: "Unknown option: \(argument)") }
                result.positional.append(argument)
            }
            index += 1
        }

        guard ["text", "json"].contains(result.format) else { throw CLIError(message: "--format must be text or json") }
        guard ["preserve", "polite", "plain"].contains(result.style) else { throw CLIError(message: "Invalid --style") }
        guard ["low", "medium", "high"].contains(result.reasoningEffort) else { throw CLIError(message: "Invalid --reasoning-effort") }
        let modes = (result.useStdin ? 1 : 0) + (result.file == nil ? 0 : 1) + (result.positional.isEmpty ? 0 : 1)
        guard modes <= 1 else { throw CLIError(message: "Use only one of --stdin, --file, or positional text") }
        return result
    }

    private static func readInput(_ arguments: ProofreadArguments) throws -> String {
        if let file = arguments.file {
            return try String(contentsOfFile: file, encoding: .utf8)
        }
        if !arguments.positional.isEmpty {
            return arguments.positional.joined(separator: " ")
        }
        if arguments.useStdin || !standardInputIsTerminal {
            return String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
        }
        throw CLIError(message: "No input text. Pass text, --stdin, or --file")
    }

    private static var standardInputIsTerminal: Bool {
        #if os(Windows)
        _isatty(_fileno(stdin)) != 0
        #else
        isatty(fileno(stdin)) != 0
        #endif
    }

    private static func writeError(_ error: Error, format: String) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let sarashinaError = error as? SarashinaError
        if format == "json" {
            let escaped = message.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let code = sarashinaError?.code ?? "cli_error"
            let output = "{\"error\":{\"code\":\"\(code)\",\"message\":\"\(escaped)\",\"retryable\":\(sarashinaError?.retryable ?? false)}}\n"
            FileHandle.standardError.write(Data(output.utf8))
        } else {
            FileHandle.standardError.write(Data("sarashina: \(message)\n".utf8))
        }
    }

    private static func exitCode(for error: Error) -> Int {
        if error is CLIError || error is ProofreadingError { return 2 }
        guard let error = error as? SarashinaError else { return 1 }
        if error.code == "missing_api_key" { return 2 }
        if error.code == "unauthorized" || error.status == 401 { return 3 }
        return error.retryable ? 4 : 1
    }
}
