import Foundation

/// Result of running a subprocess.
public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var isSuccess: Bool { exitCode == 0 }
    public var combinedOutput: String {
        let s = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return e }
        if e.isEmpty { return s }
        return "\(s)\n\(e)"
    }
}

public enum ProcessRunnerError: LocalizedError, Sendable {
    case launchFailed(String)
    case appleScriptFailed(code: Int, message: String)
    case userCancelled

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let m): return "Failed to launch process: \(m)"
        case .appleScriptFailed(let code, let m):
            return "Privileged command failed (\(code)): \(m)"
        case .userCancelled: return "User cancelled the authorization prompt."
        }
    }
}

/// Small helpers for running shell commands and privileged commands. Privileged
/// commands go through `NSAppleScript` so macOS shows the standard authorization
/// prompt instead of us prompting in-app for a password we'd have to handle.
public enum ProcessRunner {

    /// Single-quote a string for `/bin/sh -c` command lines.
    public static func shellQuote(_ argument: String) -> String {
        "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Run a binary with arguments and capture stdout/stderr. Non-blocking on the caller.
    public static func run(
        _ executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ProcessResult, Error>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: executable)
            proc.arguments = arguments
            if let environment {
                proc.environment = environment
            }

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe

            proc.terminationHandler = { p in
                let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                let result = ProcessResult(
                    exitCode: p.terminationStatus,
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? ""
                )
                cont.resume(returning: result)
            }

            do {
                try proc.run()
            } catch {
                cont.resume(throwing: ProcessRunnerError.launchFailed(error.localizedDescription))
            }
        }
    }

    /// Execute a shell command line as root via the macOS authorization prompt.
    /// Returns combined stdout/stderr on success. The user will be presented with
    /// the standard "App is trying to make changes" password dialog.
    public static func runPrivileged(
        shellCommand: String,
        prompt: String? = nil
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try runPrivilegedSync(shellCommand: shellCommand, prompt: prompt)
        }.value
    }

    private static func runPrivilegedSync(shellCommand: String, prompt: String?) throws -> String {
        // Escape any embedded double quotes in the shell command so it survives being
        // wrapped inside an AppleScript string literal.
        let escapedShell = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        var script = "do shell script \"\(escapedShell)\" with administrator privileges"
        if let prompt, !prompt.isEmpty {
            let escapedPrompt = prompt
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            script = "do shell script \"\(escapedShell)\" with prompt \"\(escapedPrompt)\" with administrator privileges"
        }

        guard let appleScript = NSAppleScript(source: script) else {
            throw ProcessRunnerError.launchFailed("Failed to compile AppleScript")
        }

        var errorInfo: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&errorInfo)

        if let errorInfo {
            // -128 == user cancelled
            let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? -1
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error"
            if code == -128 {
                throw ProcessRunnerError.userCancelled
            }
            throw ProcessRunnerError.appleScriptFailed(code: code, message: message)
        }

        return descriptor.stringValue ?? ""
    }
}
