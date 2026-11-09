import Foundation

/// Describes a configuration option accepted by a kotlinc compiler plugin JAR.
public struct JvmPluginOption: Codable, Sendable {
    public let name: String
    public let description: String
    public let required: Bool

    public init(name: String, description: String, required: Bool) {
        self.name = name
        self.description = description
        self.required = required
    }
}

/// Metadata extracted from a kotlinc compiler plugin JAR by the JVM host.
public struct JvmPluginInspectionResult: Codable, Sendable {
    public let pluginId: String
    public let commandLineProcessor: String
    public let registrar: String
    public let options: [JvmPluginOption]

    public init(
        pluginId: String,
        commandLineProcessor: String,
        registrar: String,
        options: [JvmPluginOption]
    ) {
        self.pluginId = pluginId
        self.commandLineProcessor = commandLineProcessor
        self.registrar = registrar
        self.options = options
    }
}

/// Errors occurring during JVM compiler plugin hosting and inspection.
public enum JvmPluginError: Error, LocalizedError, Sendable {
    case javaNotFound
    case hostRunnerNotFound
    case executionFailed(exitCode: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .javaNotFound:
            return "Java runtime (java) was not found in PATH or JAVA_HOME."
        case .hostRunnerNotFound:
            return "JvmPluginHost.java was not found."
        case let .executionFailed(exitCode, message):
            return "JVM plugin host failed with exit code \(exitCode): \(message)"
        }
    }
}

/// Client that manages communication with the external JVM plugin host runner.
public final class JvmPluginHostClient: @unchecked Sendable {
    public static let shared = JvmPluginHostClient()

    private init() {}

    public func findJavaExecutable() -> String? {
        if let javaHome = ProcessInfo.processInfo.environment["JAVA_HOME"] {
            let candidate = (javaHome as NSString).appendingPathComponent("bin/java")
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        let commonPaths = [
            "/opt/homebrew/bin/java",
            "/usr/bin/java",
            "/usr/local/bin/java",
        ]
        for p in commonPaths {
            if FileManager.default.isExecutableFile(atPath: p) {
                return p
            }
        }
        // Fallback: look in PATH
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let candidate = (String(dir) as NSString).appendingPathComponent("java")
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    public func findKotlinCompilerJar() -> String? {
        if let env = ProcessInfo.processInfo.environment["KSWIFTK_KOTLIN_COMPILER_JAR"],
           FileManager.default.fileExists(atPath: env) {
            return env
        }
        let commonCandidates = [
            "/opt/homebrew/Cellar/kotlin/2.4.21/libexec/lib/kotlin-compiler.jar",
            "/usr/local/Cellar/kotlin/2.4.21/libexec/lib/kotlin-compiler.jar",
        ]
        for c in commonCandidates {
            if FileManager.default.fileExists(atPath: c) {
                return c
            }
        }
        return nil
    }

    public func findJvmPluginHostSource() -> String? {
        let cwd = FileManager.default.currentDirectoryPath
        let candidates = [
            (cwd as NSString).appendingPathComponent("Scripts/jvm_plugin_host/JvmPluginHost.java"),
        ]
        for c in candidates {
            if FileManager.default.fileExists(atPath: c) {
                return c
            }
        }
        return nil
    }

    public func inspectPlugin(pluginJarPath: String) throws -> JvmPluginInspectionResult {
        guard let javaBin = findJavaExecutable() else {
            throw JvmPluginError.javaNotFound
        }
        guard let hostSource = findJvmPluginHostSource() else {
            throw JvmPluginError.hostRunnerNotFound
        }
        let compilerJar = findKotlinCompilerJar() ?? "-"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: javaBin)
        process.arguments = [
            hostSource,
            "inspect",
            pluginJarPath,
            compilerJar,
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "unknown error"
            throw JvmPluginError.executionFailed(exitCode: process.terminationStatus, message: errMsg)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(JvmPluginInspectionResult.self, from: data)
    }
}

/// Adapter wrapping an external kotlinc compiler plugin JAR as a KSwiftK `CompilerPlugin`.
struct JvmCompilerPlugin: CompilerPlugin {
    let id: String
    let jarPath: String
    let descriptor: JvmPluginInspectionResult

    init(jarPath: String, descriptor: JvmPluginInspectionResult) {
        self.jarPath = jarPath
        self.descriptor = descriptor
        self.id = descriptor.pluginId.isEmpty ? (jarPath as NSString).lastPathComponent : descriptor.pluginId
    }

    func applySemaTransform(_ context: CompilerPluginSemaContext) {
        // Validate configured options against the plugin JAR's declared CommandLineProcessor options
        let knownOptions = Set(descriptor.options.map(\.name))
        guard !knownOptions.isEmpty else { return }

        if let configured = context.pluginConfig.values[id] {
            for key in configured.keys {
                if !knownOptions.contains(key) {
                    context.diagnostics.warning(
                        "KSWIFTK-PLUGIN-0001",
                        "Plugin '\(id)' does not recognize option '\(key)'. Available options: \(descriptor.options.map(\.name).joined(separator: ", "))",
                        range: nil
                    )
                }
            }
        }
    }
}
