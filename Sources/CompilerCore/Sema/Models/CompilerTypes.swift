import Foundation

public struct TargetTriple: Equatable, Sendable {
    public let arch: String
    public let vendor: String
    public let os: String
    public let osVersion: String?

    public init(arch: String, vendor: String, os: String, osVersion: String?) {
        self.arch = arch
        self.vendor = vendor
        self.os = os
        self.osVersion = osVersion
    }

    public static func hostDefault() -> TargetTriple {
        #if arch(arm64)
            let arch = "arm64"
        #elseif arch(x86_64)
            let arch = "x86_64"
        #else
            let arch = "arm64"
        #endif
        #if os(Linux)
            let linuxArch = arch == "arm64" ? "aarch64" : arch
            return TargetTriple(arch: linuxArch, vendor: "unknown", os: "linux-gnu", osVersion: nil)
        #else
            return TargetTriple(arch: arch, vendor: "apple", os: "macosx", osVersion: nil)
        #endif
    }

    /// Canonical spelling used in `.kklib` manifests and diagnostics for a
    /// WASI-hosted wasm32 target.
    public static let wasmWASI = TargetTriple(
        arch: "wasm32", vendor: "unknown", os: "wasi", osVersion: nil
    )

    /// Canonical spelling for a JS/browser-hosted wasm32 target.
    public static let wasmJS = TargetTriple(
        arch: "wasm32", vendor: "unknown", os: "js", osVersion: nil
    )

    /// Whether this target describes a WebAssembly module (`wasm32`/`wasm64`).
    public var isWasm: Bool { arch.hasPrefix("wasm") }

    /// Whether this is a WASI-hosted wasm target (`wasi`, `wasi-p1`, `wasip1`...).
    public var isWASI: Bool {
        isWasm && (os == "wasi" || os.hasPrefix("wasip") || os.hasPrefix("wasi-"))
    }

    /// Whether this is a JS/browser-hosted wasm target (`js` OS tag).
    public var isWasmJS: Bool { isWasm && os == "js" }
}

public enum OptimizationLevel: Int {
    case O0
    case O1
    case O2
    case O3
}

public enum EmitMode: String, Sendable {
    case executable
    case object
    case llvmIR
    case kirDump
    case library
    case jvmClass
    case jvmJar

    public var isJVM: Bool { self == .jvmClass || self == .jvmJar }
}

public enum NameBasedDestructuringMode: String, Equatable {
    case disabled
    case complete
}

/// Thread-safety mode for `by lazy { }` delegates (P5-80).
public enum LazyDelegateThreadSafetyMode: Int, Equatable {
    /// `LazyThreadSafetyMode.SYNCHRONIZED` – uses a lock (default).
    case synchronized = 1
    /// `LazyThreadSafetyMode.NONE` – no synchronization.
    case none = 0
    /// `LazyThreadSafetyMode.PUBLICATION` – concurrent initializers may race, but only one result is published.
    case publication = 2
}

public enum DiagnosticsFormat: String, Equatable {
    case text
    /// JSON format conforming to the LSP diagnostic schema.
    case json
}

public struct CompilerOptions: Equatable {
    public var moduleName: String
    public var inputs: [String]
    public var outputPath: String
    public var emit: EmitMode
    public var searchPaths: [String]
    public var libraryPaths: [String]
    public var linkLibraries: [String]
    public var target: TargetTriple
    public var optLevel: OptimizationLevel
    public var debugInfo: Bool
    public var frontendFlags: [String]
    public var irFlags: [String]
    public var runtimeFlags: [String]
    public var diagnosticsFormat: DiagnosticsFormat
    /// Exact file-level entry point, used by generated test executables.
    public var entryPointFQName: String?
    /// JVM classpath entries, in lookup order (JAR files or class directories).
    public var jvmClasspath: [String]

    /// `kswiftc --run`: execute the program right after compiling it, using the
    /// KIR interpreter when it covers the program (see `KIRInterpreter`).
    public var runsImmediately: Bool {
        frontendFlags.contains("run")
    }

    public var nameBasedDestructuringMode: NameBasedDestructuringMode {
        frontendFlags.contains("name-based-destructuring=complete")
            || frontendFlags.contains("-Xname-based-destructuring=complete")
            ? .complete
            : .disabled
    }

    /// Whether this compilation produces common-module metadata that may
    /// retain expect declarations without local actual declarations.
    public var isCommonModule: Bool {
        emit == .library || frontendFlags.contains("common-module")
    }

    public var stdlibSearchPaths: [String]
    public var includeStdlib: Bool

    /// Path to the incremental compilation cache directory, if any.
    /// Incremental compilation is enabled when either this is non-nil or the
    /// `incremental` frontend flag is set, unless `no-incremental` is set.
    /// Without an explicit path the cache
    /// lives in the compiler-managed per-user cache directory, never in the
    /// workspace. When enabled and an authenticated cache is available, exact
    /// no-op builds restore the previous output artifact.
    public var incrementalCachePath: String?

    /// When true, compile only the bundled/residual stdlib into a .kklib.
    public var stdlibOnly: Bool
    /// Path to a prebuilt stdlib .kklib. Disables bundled source injection.
    public var stdlibLibraryPath: String?
    /// Whether the compiler may resolve the process default stdlib artifact.
    /// CLI debug runs can disable this with `--stdlib-from-source`.
    public var allowDefaultStdlibLibrary: Bool
    /// Which bundled stdlib sources are injected, and which default artifact
    /// is resolved (`--profile`, KUU-3016). An explicit `stdlibLibraryPath`
    /// must have been built for the same profile.
    public var stdlibProfile: StdlibProfile

    /// Search paths ordered with stdlibLibraryPath first and duplicates removed.
    public var effectiveLibrarySearchPaths: [String] {
        var result: [String] = []
        var seen: Set<String> = []
        let all = (stdlibLibraryPath.map { [$0] } ?? []) + searchPaths
        for path in all {
            let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }
        return result
    }

    /// Optional path to a prebuilt stdlib `.kklib` used as a fallback when a
    /// compilation requests bundled stdlib. Test support sets this once per
    /// process to share a single compiled stdlib artifact across many tests.
    /// Compilations that must exercise the bundled-source injection path opt out
    /// with `allowDefaultStdlibLibrary: false`.
    nonisolated(unsafe) public static var defaultStdlibLibraryPath: String? = nil

    /// Returns whether the process default stdlib artifact applies to a run.
    /// All emit modes share the artifact-backed default. Source/introspection
    /// callers opt out with `allowDefaultStdlibLibrary: false`; building the
    /// stdlib itself must always use its sources.
    public static func shouldUseDefaultStdlib(
        allowDefaultStdlibLibrary: Bool,
        includeStdlib: Bool,
        stdlibOnly: Bool,
        stdlibLibraryPath: String?,
        emit: EmitMode
    ) -> Bool {
        !emit.isJVM && allowDefaultStdlibLibrary && includeStdlib && !stdlibOnly
            && stdlibLibraryPath == nil
    }

    public init(
        moduleName: String,
        inputs: [String],
        outputPath: String,
        emit: EmitMode,
        searchPaths: [String] = [],
        libraryPaths: [String] = [],
        linkLibraries: [String] = [],
        target: TargetTriple,
        optLevel: OptimizationLevel = .O0,
        debugInfo: Bool = false,
        frontendFlags: [String] = [],
        irFlags: [String] = [],
        runtimeFlags: [String] = [],
        stdlibSearchPaths: [String] = [],
        includeStdlib: Bool = true,
        incrementalCachePath: String? = nil,
        diagnosticsFormat: DiagnosticsFormat = .text,
        stdlibOnly: Bool = false,
        stdlibLibraryPath: String? = nil,
        allowDefaultStdlibLibrary: Bool = true,
        entryPointFQName: String? = nil,
        jvmClasspath: [String] = [],
        stdlibProfile: StdlibProfile = .full
    ) {
        self.moduleName = moduleName
        self.inputs = inputs
        self.outputPath = outputPath
        self.emit = emit
        self.searchPaths = searchPaths
        self.libraryPaths = libraryPaths
        self.linkLibraries = linkLibraries
        self.target = target
        self.optLevel = optLevel
        self.debugInfo = debugInfo
        self.frontendFlags = frontendFlags
        self.irFlags = irFlags
        self.runtimeFlags = runtimeFlags
        self.stdlibSearchPaths = stdlibSearchPaths
        self.allowDefaultStdlibLibrary = allowDefaultStdlibLibrary

        let shouldUseDefaultStdlib = Self.shouldUseDefaultStdlib(
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            includeStdlib: includeStdlib,
            stdlibOnly: stdlibOnly,
            stdlibLibraryPath: stdlibLibraryPath,
            emit: emit
        )
        let resolvedStdlibLibraryPath = stdlibLibraryPath ?? (shouldUseDefaultStdlib ? Self.defaultStdlibLibraryPath : nil)
        self.stdlibLibraryPath = resolvedStdlibLibraryPath
        self.includeStdlib = !emit.isJVM && includeStdlib && resolvedStdlibLibraryPath == nil

        self.incrementalCachePath = incrementalCachePath
        self.diagnosticsFormat = diagnosticsFormat
        self.stdlibOnly = stdlibOnly
        self.entryPointFQName = entryPointFQName
        self.jvmClasspath = jvmClasspath
        self.stdlibProfile = stdlibProfile
    }

    /// Default search paths for locating Kotlin stdlib sources.
    ///
    /// Checks candidates in order and returns only paths that exist on disk:
    /// 1. `KSWIFTK_STDLIB_PATH` environment variable (if set).
    /// 2. `<prefix>/lib/kswiftk/stdlib` relative to the compiler binary (macOS).
    public static func defaultStdlibSearchPaths() -> [String] {
        let fileManager = FileManager.default
        var paths: [String] = []

        if let envPath = ProcessInfo.processInfo.environment["KSWIFTK_STDLIB_PATH"],
           !envPath.isEmpty,
           fileManager.fileExists(atPath: envPath)
        {
            paths.append(envPath)
        }

        #if os(macOS)
            if let execPath = CommandLine.arguments.first, !execPath.isEmpty {
                let execURL = URL(fileURLWithPath: execPath).resolvingSymlinksInPath()
                let prefixDir = execURL.deletingLastPathComponent().deletingLastPathComponent()
                let stdlibDir = prefixDir.appendingPathComponent("lib/kswiftk/stdlib").path
                if fileManager.fileExists(atPath: stdlibDir) {
                    paths.append(stdlibDir)
                }
            }
        #endif

        return paths
    }

    /// Marker annotations accepted by compiler-wide `-opt-in=<fqName>` flags.
    public var optInMarkerNames: [String] {
        Self.optInMarkerNames(from: frontendFlags)
    }

    public static func optInMarkerNames(from frontendFlags: [String]) -> [String] {
        var names: [String] = []
        for flag in frontendFlags {
            let trimmed = flag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let prefixes = ["opt-in=", "opt-in:"]
            guard let prefix = prefixes.first(where: { trimmed.hasPrefix($0) }) else {
                continue
            }
            let rawValue = String(trimmed.dropFirst(prefix.count))
            for name in rawValue.split(separator: ",") {
                let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty {
                    names.append(normalized)
                }
            }
        }
        return names
    }

    /// The number of frontend parallel jobs parsed from `-Xfrontend jobs=N`.
    /// Controls BuildASTPhase concurrency and, with sema-parallel enabled,
    /// independent Sema preparation/body workers. LexPhase and ParsePhase
    /// always submit all file tasks concurrently (unchanged from pre-PR
    /// behaviour).  Returns 1 (sequential) when the flag is not present.
    public var frontendJobs: Int {
        for flag in frontendFlags {
            if flag.hasPrefix("jobs="),
               let n = Int(flag.dropFirst(5)),
               n >= 1
            {
                return n
            }
        }
        return 1
    }

    /// Thread-safety mode for `by lazy { }` delegates, parsed from
    /// `-Xfrontend lazy-thread-safety=SYNCHRONIZED|PUBLICATION|NONE`.
    /// Defaults to `.synchronized` when the flag is absent.
    public var lazyThreadSafetyMode: LazyDelegateThreadSafetyMode {
        for flag in frontendFlags where flag.hasPrefix("lazy-thread-safety=") {
            let value = String(flag.dropFirst("lazy-thread-safety=".count))
                .uppercased()
            switch value {
            case "NONE":
                return .none
            case "SYNCHRONIZED":
                return .synchronized
            case "PUBLICATION":
                return .publication
            default:
                return .synchronized
            }
        }
        return .synchronized
    }

    /// Controls whether runtime reflection metadata includes non-public symbols.
    /// Set with `-Xruntime reflection-metadata=all`.
    /// Defaults to `false` for public-only metadata.
    public var includeNonPublicReflectionMetadata: Bool {
        runtimeFlags.contains("reflection-metadata=all")
    }

    /// Kotlin's new inference mode. Accepts either the raw compiler argument
    /// spelling (`-Xnew-inference`) or the normalized frontend flag
    /// (`new-inference`) for compatibility with direct tests and CLI parsing.
    public var useNewInference: Bool {
        frontendFlags.contains("-Xnew-inference") || frontendFlags.contains("new-inference")
    }

    /// Enables unrestricted builder inference. Accepts either the raw compiler
    /// argument spelling or the normalized frontend flag.
    public var useUnrestrictedBuilderInference: Bool {
        frontendFlags.contains("-Xunrestricted-builder-inference")
            || frontendFlags.contains("unrestricted-builder-inference")
    }

    public var useProperTypeInferenceConstraintsProcessing: Bool {
        frontendFlags.contains("ProperTypeInferenceConstraintsProcessing")
            || frontendFlags.contains("proper-type-inference-constraints-processing")
    }

    /// Enables Kotlin's experimental full value class declaration rules.
    /// Accept the compiler option spelling and the language feature name used
    /// by Kotlin's test directives so both CLI and direct frontend clients can
    /// select the same mode.
    public var fullValueClassesEnabled: Bool {
        frontendFlags.contains("full-value-classes")
            || frontendFlags.contains("-Xfull-value-classes")
            || frontendFlags.contains("FullValueClasses")
            || frontendFlags.contains("+FullValueClasses")
    }

    /// Enables implicit conversion of signed integer constants to unsigned
    /// parameter types when both sides carry `@ImplicitIntegerCoercion`.
    public var implicitSignedToUnsignedIntegerConversionEnabled: Bool {
        frontendFlags.contains("ImplicitSignedToUnsignedIntegerConversion")
            || frontendFlags.contains("+ImplicitSignedToUnsignedIntegerConversion")
    }
}
