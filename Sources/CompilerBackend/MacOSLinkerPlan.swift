import CompilerCore
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Reuses the Swift driver's single clang link job. Compatibility archives,
/// SDK paths and deployment flags stay owned by the selected Swift toolchain.
/// Debug links (which can also run dsymutil) continue to use the driver.
struct MacOSLinkerPlan: Codable {
    let cacheKey: String
    let executable: String
    let arguments: [String]
    let dependencies: [String: String]

    private static let lock = NSLock()
    private static let outputMarker = "/__kswiftk_link_output__"

    func linkArguments(inputs: [String], output: String, libraryPaths: [String], libraries: [String], droppingForceLoads: Bool = false) -> [String] {
        let planArguments = droppingForceLoads ? argumentsWithoutForceLoads : arguments
        return inputs + planArguments.map { $0 == Self.outputMarker ? output : $0 }
            + libraryPaths.map { "-L\($0)" } + libraries.map { "-l\($0)" }
    }

    /// Absolute paths the driver force-loads via `-force_load <path>` pairs.
    /// `nil` when a `-force_load` token lacks an absolute-path argument — an
    /// argument shape the caller must not rewrite.
    var forceLoadedPaths: [String]? {
        var paths: [String] = []
        var index = arguments.startIndex
        while index < arguments.endIndex {
            if arguments[index] == "-force_load" {
                guard index + 1 < arguments.endIndex, arguments[index + 1].hasPrefix("/")
                else { return nil }
                paths.append(arguments[index + 1])
                index += 2
            } else {
                index += 1
            }
        }
        return paths
    }

    private var argumentsWithoutForceLoads: [String] {
        var kept: [String] = []
        var index = arguments.startIndex
        while index < arguments.endIndex {
            if arguments[index] == "-force_load", index + 1 < arguments.endIndex {
                index += 2
            } else {
                kept.append(arguments[index])
                index += 1
            }
        }
        return kept
    }

    static func load(
        swiftcPath: String,
        driverArguments: [String],
        cacheDirectory: URL,
        phaseTimer: PhaseTimer? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        driverOutput: (() throws -> String)? = nil
    ) throws -> MacOSLinkerPlan? {
        lock.lock()
        defer { lock.unlock() }

        let key = cacheIdentity(swiftcPath: swiftcPath, driverArguments: driverArguments, environment: environment)
        let cacheURL = cacheDirectory.appendingPathComponent("\(key).json")
        if TrustedFileSystem.isTrustedDirectory(cacheDirectory.path),
           trustedCacheFile(cacheURL),
           let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(Self.self, from: data),
           cached.cacheKey == key,
           supportedArguments(executable: cached.executable, arguments: cached.arguments),
           !cached.dependencies.isEmpty,
           cached.dependencies[cached.executable] != nil,
           cached.dependencies.allSatisfy({ signature($0.key) == $0.value }),
           ["swiftc", "swift-driver"].allSatisfy({ name in
               let path = URL(fileURLWithPath: cached.executable).deletingLastPathComponent().appendingPathComponent(name).path
               return signature(path) == nil || cached.dependencies[path] != nil
           }),
           trustedExecutable(cached.executable) {
            return cached
        }

        let output: String
        if let driverOutput {
            output = try driverOutput()
        } else {
            let result = try CommandRunner.run(
                executable: swiftcPath,
                arguments: ["-###", "/dev/null", "-o", outputMarker] + driverArguments,
                phaseTimer: phaseTimer, subPhaseName: "Link/swiftc-plan"
            )
            output = result.stdout + result.stderr
        }
        guard let plan = parse(output, cacheKey: key), trustedExecutable(plan.executable) else { return nil }

        // Cache failure must not prevent linking (read-only installations, for example).
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if TrustedFileSystem.isTrustedDirectory(cacheDirectory.path),
           let data = try? JSONEncoder().encode(plan) {
            try? data.write(to: cacheURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
        }
        return plan
    }

    static func cacheIdentity(swiftcPath: String, driverArguments: [String], environment: [String: String]) -> String {
        // /usr/bin/swiftc is an xcrun shim. Include Xcode selection as well as
        // the executable identity so switching Xcode invalidates its plan.
        let selection = URL(fileURLWithPath: "/var/db/xcode_select_link").resolvingSymlinksInPath().path
        let developer = environment["DEVELOPER_DIR"] ?? selection
        let versionPath = URL(fileURLWithPath: developer).deletingLastPathComponent()
            .appendingPathComponent("version.plist").path
        let relevantEnvironment = environment.filter {
            ["DEVELOPER_DIR", "TOOLCHAINS", "SDKROOT", "PATH", "MACOSX_DEPLOYMENT_TARGET"].contains($0.key)
                || $0.key.hasPrefix("SWIFT_")
        }.map { "\($0.key)=\($0.value)" }.sorted()
        let parts = ["macos-link-plan-v1", swiftcPath, signature(swiftcPath) ?? "missing", selection,
                     signature(versionPath) ?? "missing"] + driverArguments + relevantEnvironment
        return CodegenRuntimeSupport.stableFNV1a64Hex(parts.joined(separator: "\u{0}"))
    }

    static func parse(_ output: String, cacheKey: String) -> MacOSLinkerPlan? {
        let lines = output.split(whereSeparator: \.isNewline)
        guard lines.count == 1, let tokens = tokenize(String(lines[0])),
              let executable = tokens.first, executable.hasPrefix("/"),
              URL(fileURLWithPath: executable).lastPathComponent == "clang",
              tokens.filter({ $0 == "/dev/null" }).count == 1,
              tokens.filter({ $0 == outputMarker }).count == 1,
              !tokens.contains(where: { $0.hasPrefix("@") }),
              let outputIndex = tokens.firstIndex(of: "-o"),
              outputIndex + 1 < tokens.count, tokens[outputIndex + 1] == outputMarker
        else { return nil }
        let arguments = Array(tokens.dropFirst()).filter { $0 != "/dev/null" }
        var dependencies: [String: String] = [:]
        for path in tokens where path.hasPrefix("/") && path != "/dev/null" && path != outputMarker {
            guard let value = signature(path) else { return nil }
            dependencies[path] = value
            // SDK/toolchain metadata can change without the directory mtime changing.
            for name in ["SDKSettings.json", "SDKSettings.plist"] {
                let metadata = URL(fileURLWithPath: path).appendingPathComponent(name).path
                if let value = signature(metadata) { dependencies[metadata] = value }
            }
        }
        // With an xcrun shim, the selected toolchain's real driver can change
        // independently of /usr/bin/swiftc and the clang binary.
        let toolchainBin = URL(fileURLWithPath: executable).deletingLastPathComponent()
        for name in ["swiftc", "swift-driver"] {
            let path = toolchainBin.appendingPathComponent(name).path
            if let value = signature(path) { dependencies[path] = value }
        }
        return Self(cacheKey: cacheKey, executable: executable, arguments: arguments, dependencies: dependencies)
    }

    private static func supportedArguments(executable: String, arguments: [String]) -> Bool {
        guard executable.hasPrefix("/"), URL(fileURLWithPath: executable).lastPathComponent == "clang",
              arguments.filter({ $0 == outputMarker }).count == 1,
              !arguments.contains("/dev/null"),
              !arguments.contains(where: { $0.hasPrefix("@") }),
              let outputIndex = arguments.firstIndex(of: "-o"), outputIndex + 1 < arguments.count
        else { return false }
        return arguments[outputIndex + 1] == outputMarker
    }

    /// Decode the driver's shell-escaped display without invoking a shell.
    static func tokenize(_ line: String) -> [String]? {
        var tokens: [String] = []
        var token = ""
        var quote: Character?
        var escaped = false
        var started = false
        for character in line {
            if escaped {
                token.append(character)
                escaped = false
            } else if character == "\\", quote != "'" {
                escaped = true
                started = true
            } else if let currentQuote = quote {
                if character == currentQuote { quote = nil } else { token.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
                started = true
            } else if character.isWhitespace {
                if started { tokens.append(token); token = ""; started = false }
            } else {
                token.append(character)
                started = true
            }
        }
        guard quote == nil, !escaped else { return nil }
        if started { tokens.append(token) }
        return tokens
    }

    static func signature(_ path: String) -> String? {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved) else { return nil }
        return [resolved, String(describing: attributes[.size]), String(describing: (attributes[.modificationDate] as? Date)?.timeIntervalSince1970),
                String(describing: attributes[.systemFileNumber]), String(describing: attributes[.posixPermissions])]
            .joined(separator: "\u{0}")
    }

    private static func trustedExecutable(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return FileManager.default.isExecutableFile(atPath: path)
            && CommandRunner.resolveExecutable(url.lastPathComponent, fallback: "", pathEnvironment: url.deletingLastPathComponent().path) == path
    }

    static func trustedCacheFile(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value,
              permissions & 0o022 == 0,
              let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value
        else { return false }
        return owner == getuid()
    }
}
