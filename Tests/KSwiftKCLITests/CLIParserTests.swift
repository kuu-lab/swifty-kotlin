#if canImport(Testing)
@testable import CompilerCore
@testable import KSwiftKCLI
import Testing

// .serialized: parsesStdlibFlags() and
// defaultEmitModesHonorProcessDefaultStdlibLibrary() both mutate the
// process-wide CompilerOptions.defaultStdlibLibraryPath; running this
// suite's tests concurrently races on that global.
@Suite("CLI.Parser", .serialized)
struct CLIParserTests {
    @Test(arguments: ["class", "jar"])
    func parsesM22JVMStdlibBuild(mode: String) throws {
        for args in [["--stdlib-only", "--emit", mode], ["--emit", mode, "--no-stdlib", "--stdlib-only"]] {
            let options = try CLIParser.parse(args: args)
            #expect(options.stdlibOnly)
            #expect(options.inputs.isEmpty)
            #expect(options.emit == (mode == "jar" ? .jvmJar : .jvmClass))
            #expect(options.outputPath == (mode == "jar" ? "./kswiftk-stdlib.jar" : "./classes"))
            #expect(!options.includeStdlib)
        }
    }

    @Test
    func parsesStdlibProfile() throws {
        #expect(try CLIParser.parse(args: ["hello.kt"]).stdlibProfile == .full)
        #expect(try CLIParser.parse(args: ["--profile", "full", "hello.kt"]).stdlibProfile == .full)
        #expect(try CLIParser.parse(args: ["--profile", "minimal", "hello.kt"]).stdlibProfile == .minimal)
        #expect(try CLIParser.parse(args: ["--stdlib-only", "--profile", "minimal"]).stdlibProfile == .minimal)
        #expect(throws: CLIParseError.unsupportedStdlibProfile("tiny")) {
            try CLIParser.parse(args: ["--profile", "tiny", "hello.kt"])
        }
        #expect(throws: CLIParseError.missingValue("--profile")) {
            try CLIParser.parse(args: ["--profile"])
        }
        #expect(throws: CLIParseError.incompatibleStdlibOptions("--profile minimal is not supported with --emit class or jar")) {
            try CLIParser.parse(args: ["--profile", "minimal", "--emit", "jar", "hello.kt"])
        }
    }

    @Test(arguments: ["class", "jar"])
    func parsesJVMOutputModes(mode: String) throws {
        let options = try CLIParser.parse(args: ["--emit", mode, "hello.kt"])
        #expect(options.emit == (mode == "class" ? .jvmClass : .jvmJar))
        #expect(options.outputPath == (mode == "class" ? "./classes" : "./main.jar"))
        #expect(!options.includeStdlib)
        #expect(options.stdlibLibraryPath == nil)
        #expect(!CompilerOptions.shouldUseDefaultStdlib(
            allowDefaultStdlibLibrary: true, includeStdlib: true, stdlibOnly: false,
            stdlibLibraryPath: nil, emit: options.emit
        ))
        let explicit = try CLIParser.parse(args: ["-o", "custom", "--emit", mode, "hello.kt"])
        #expect(explicit.outputPath == "custom")
    }

    @Test(arguments: ["--classpath", "-classpath", "-cp"])
    func parsesJVMClasspath(flag: String) throws {
        let options = try CLIParser.parse(args: ["--emit", "jar", flag, "a.jar::classes", flag, "b.jar", "hello.kt"])
        #expect(options.jvmClasspath == ["a.jar", ".", "classes", "b.jar"])
        #expect(throws: CLIParseError.missingValue(flag)) { try CLIParser.parse(args: [flag]) }
        #expect(throws: CLIParseError.incompatibleStdlibOptions("--classpath requires --emit class or jar")) { try CLIParser.parse(args: [flag, "a.jar", "hello.kt"]) }
    }

    @Test(arguments: ["--test", "-generate-test-runner"])
    func parsesTestRunnerFlag(flag: String) throws {
        let options = try CLIParser.parse(args: [flag, "tests.kt"])
        #expect(options.frontendFlags.contains("generate-test-runner"))
        #expect(options.emit == .executable)
    }
    @Test
    func selectsQualifiedExecutableEntryWithoutRewritingLibraryMains() throws {
        let options = try CLIParser.parse(args: [
            "--entry-point", "consumer.main", "--stdlib-from-source", "producer.kt", "consumer.kt",
        ])
        #expect(options.entryPointFQName == "consumer.main")
        #expect(options.inputs == ["producer.kt", "consumer.kt"])
        #expect(options.includeStdlib && !options.allowDefaultStdlibLibrary)
        #expect(throws: CLIParseError.missingValue("--entry-point")) {
            try CLIParser.parse(args: ["input.kt", "--entry-point"])
        }
    }

    @Test
    func parsesMinimalInput() throws {
        let options = try CLIParser.parse(args: ["input.kt"])
        #expect(options.inputs == ["input.kt"])
        #expect(options.outputPath == "./a.out")
        #expect(options.moduleName == "Main")
        #expect(options.emit == .executable)
        #expect(options.incrementalCachePath == nil)
        #expect(!options.frontendFlags.contains("incremental"))
    }

    @Test
    func parsesOptionsAndFlags() throws {
        let options = try CLIParser.parse(args: [
            "-o", "out.bin",
            "-m", "Demo",
            "--emit", "kir",
            "-O2",
            "-I", "include",
            "-L", "lib",
            "-l", "runtime",
            "--target", "x86_64-apple-macos",
            "-Xfrontend", "time-phases",
            "-Xfrontend", "common-module",
            "-Xir", "trace-lowering",
            "-Xruntime", "trace=true",
            "-g",
            "main.kt",
        ])

        #expect(options.outputPath == "out.bin")
        #expect(options.moduleName == "Demo")
        #expect(options.emit == .kirDump)
        #expect(options.optLevel == .O2)
        #expect(options.searchPaths == ["include"])
        #expect(options.libraryPaths == ["lib"])
        #expect(options.linkLibraries == ["runtime"])
        #expect(options.frontendFlags == ["time-phases", "common-module"])
        #expect(options.isCommonModule)
        #expect(options.irFlags == ["trace-lowering"])
        #expect(options.runtimeFlags == ["trace=true"])
        #expect(options.debugInfo)
        #expect(options.inputs == ["main.kt"])
        #expect(options.target.arch == "x86_64")
        #expect(options.target.vendor == "apple")
        #expect(options.target.os == "macos")
    }

    @Test
    func parsesCompleteNameBasedDestructuringMode() throws {
        let options = try CLIParser.parse(args: [
            "-Xname-based-destructuring=complete", "main.kt",
        ])
        #expect(options.nameBasedDestructuringMode == .complete)
        #expect(throws: CLIParseError.unsupportedNameBasedDestructuringMode("only-syntax")) {
            try CLIParser.parse(args: ["-Xname-based-destructuring=only-syntax", "main.kt"])
        }
    }

    @Test(arguments: ["--incremental", "-Xfrontend"])
    func parsesIncrementalEnableFlag(flag: String) throws {
        let flags = flag == "-Xfrontend" ? [flag, "incremental"] : [flag]
        let options = try CLIParser.parse(args: flags + ["input.kt"])
        #expect(options.frontendFlags == ["incremental"])
        #expect(options.incrementalCachePath == nil)
    }

    @Test
    func parsesIncrementalCachePathAndDisableFlag() throws {
        let options = try CLIParser.parse(args: [
            "--incremental-cache", "build/cache with spaces",
            "--no-incremental", "--incremental", "input.kt",
        ])
        #expect(options.incrementalCachePath == "build/cache with spaces")
        #expect(options.frontendFlags == ["no-incremental", "incremental"])
        for arguments in [
            ["input.kt", "--incremental-cache"],
            ["input.kt", "--incremental-cache", ""],
            ["input.kt", "--incremental-cache", "--no-incremental"],
        ] {
            #expect(throws: CLIParseError.missingValue("--incremental-cache")) {
                try CLIParser.parse(args: arguments)
            }
        }
    }

    @Test
    func parsesReflectionMetadataRuntimeFlag() throws {
        let options = try CLIParser.parse(args: [
            "-Xruntime",
            "reflection-metadata=all",
            "main.kt",
        ])

        #expect(options.runtimeFlags == ["reflection-metadata=all"])
        #expect(options.runtimeFlags.contains("reflection-metadata=all"))
        #expect(options.includeNonPublicReflectionMetadata)
    }

    @Test
    func parsesAdvancedTypeInferenceFlags() throws {
        let options = try CLIParser.parse(args: [
            "-Xnew-inference",
            "-Xunrestricted-builder-inference",
            "-Xproper-type-inference-constraints-processing",
            "main.kt",
        ])

        #expect(options.useNewInference)
        #expect(options.useUnrestrictedBuilderInference)
        #expect(options.useProperTypeInferenceConstraintsProcessing)
    }

    @Test
    func parsesOptInFlag() throws {
        let options = try CLIParser.parse(args: [
            "-opt-in=kotlin.ExperimentalVersionOverloading",
            "main.kt",
        ])

        #expect(options.frontendFlags == ["opt-in=kotlin.ExperimentalVersionOverloading"])
        #expect(options.optInMarkerNames == ["kotlin.ExperimentalVersionOverloading"])
    }

    @Test
    func parsesOptInFlagWithSeparateValue() throws {
        let options = try CLIParser.parse(args: [
            "-opt-in",
            "kotlin.ExperimentalVersionOverloading,kotlin.ExperimentalStdlibApi",
            "main.kt",
        ])

        #expect(options.frontendFlags == ["opt-in=kotlin.ExperimentalVersionOverloading,kotlin.ExperimentalStdlibApi"])
        #expect(
            options.optInMarkerNames
                == ["kotlin.ExperimentalVersionOverloading", "kotlin.ExperimentalStdlibApi"]
        )
    }

    @Test
    func throwsMissingValue() {
        #expect(throws: CLIParseError.missingValue("-o")) {
            try CLIParser.parse(args: ["-o"])
        }
    }

    @Test
    func throwsInvalidTargetTriple() {
        #expect(throws: CLIParseError.invalidTargetTriple("invalid")) {
            try CLIParser.parse(args: ["--target", "invalid", "main.kt"])
        }
    }

    @Test
    func throwsUnknownOption() {
        #expect(throws: CLIParseError.unknownOption("--unknown")) {
            try CLIParser.parse(args: ["--unknown", "main.kt"])
        }
    }

    @Test
    func parsesStdlibFlags() throws {
        // CompilerOptions.init (CompilerTypes.swift) reads the process-wide
        // CompilerOptions.defaultStdlibLibraryPath whenever
        // shouldUseDefaultStdlib(...) holds, which is exactly the CLI
        // default for the "--stdlib"/plain-args cases below (no
        // --stdlib-library, includeStdlib == true,
        // allowDefaultStdlibLibrary == true). If another test in this
        // process already published a path there (e.g. via
        // TestStdlibCache.shared.prepare(), as several CompilerCoreTests/
        // CompilerBackendTests helpers do), CLIParser.parse would silently
        // resolve stdlibLibraryPath from that global and flip includeStdlib
        // to false out from under us — see
        // defaultEmitModesHonorProcessDefaultStdlibLibrary below,
        // which pins that behavior as an intentional contract. Isolate from
        // that shared state so this test's result depends only on the CLI
        // flags being parsed.
        let savedDefaultStdlibLibraryPath = CompilerOptions.defaultStdlibLibraryPath
        defer { CompilerOptions.defaultStdlibLibraryPath = savedDefaultStdlibLibraryPath }
        CompilerOptions.defaultStdlibLibraryPath = nil

        let noStdlib = try CLIParser.parse(args: ["--no-stdlib", "main.kt"])
        #expect(noStdlib.includeStdlib == false)

        let stdlib = try CLIParser.parse(args: ["--stdlib", "main.kt"])
        #expect(stdlib.includeStdlib == true)

        let defaultOptions = try CLIParser.parse(args: ["main.kt"])
        #expect(defaultOptions.includeStdlib == true)
    }

    @Test
    func defaultEmitModesHonorProcessDefaultStdlibLibrary() throws {
        // Pins the main.swift two-phase parse contract: after resolving or
        // building a prebuilt stdlib artifact and publishing its path to
        // CompilerOptions.defaultStdlibLibraryPath, main.swift re-parses the
        // same args so CompilerOptions.init picks that path up as
        // stdlibLibraryPath and turns off source-injection stdlib
        // inclusion. This is why parsesStdlibFlags() above must isolate
        // itself from this same global.
        let saved = CompilerOptions.defaultStdlibLibraryPath
        defer { CompilerOptions.defaultStdlibLibraryPath = saved }
        CompilerOptions.defaultStdlibLibraryPath = "/tmp/KSwiftKStdlib.kklib"

        for mode in ["executable", "object", "llvm", "kir", "library"] {
            let args = ["--emit", mode, "main.kt"]
            let options = try CLIParser.parse(args: args)
            #expect(options.stdlibLibraryPath == "/tmp/KSwiftKStdlib.kklib")
            #expect(!options.includeStdlib)

            let source = try CLIParser.parse(args: ["--stdlib-from-source"] + args)
            #expect(source.stdlibLibraryPath == nil)
            #expect(source.includeStdlib)
            let noStdlib = try CLIParser.parse(args: ["--no-stdlib"] + args)
            #expect(noStdlib.stdlibLibraryPath == nil)
            #expect(!noStdlib.includeStdlib)
            let explicit = try CLIParser.parse(args: ["--stdlib-library", "/tmp/explicit.kklib"] + args)
            #expect(explicit.stdlibLibraryPath == "/tmp/explicit.kklib")
            #expect(!explicit.includeStdlib)
        }
        for mode in ["class", "jar"] {
            let options = try CLIParser.parse(args: ["--emit", mode, "main.kt"])
            #expect(options.stdlibLibraryPath == nil)
            #expect(!options.includeStdlib)
        }
        let stdlibOnly = try CLIParser.parse(args: ["--stdlib-only"])
        #expect(stdlibOnly.stdlibLibraryPath == nil)
        #expect(stdlibOnly.includeStdlib)
    }

    @Test
    func parsesStdlibOnly() throws {
        let options = try CLIParser.parse(args: ["--stdlib-only"])

        #expect(options.inputs.isEmpty)
        #expect(options.emit == .library)
        #expect(options.moduleName == "KSwiftKStdlib")
        #expect(options.stdlibOnly)
        #expect(options.stdlibLibraryPath == nil)
        #expect(options.includeStdlib)
    }

    @Test
    func parsesStdlibLibraryAndDisablesSourceInjection() throws {
        let options = try CLIParser.parse(args: ["--stdlib-library", "/tmp/KSwiftKStdlib.kklib", "main.kt"])

        #expect(options.stdlibLibraryPath == "/tmp/KSwiftKStdlib.kklib")
        #expect(!options.includeStdlib)
        #expect(!options.stdlibOnly)
    }

    @Test
    func parsesStdlibFromSourceDebugFallback() throws {
        let options = try CLIParser.parse(args: ["--stdlib-from-source", "main.kt"])

        #expect(options.allowDefaultStdlibLibrary == false)
        #expect(options.includeStdlib)
        #expect(options.stdlibLibraryPath == nil)
    }

    @Test
    func rejectsStdlibLibraryWithSourceFallback() {
        #expect(throws: CLIParseError.incompatibleStdlibOptions(
            "--stdlib-library cannot be combined with --stdlib-from-source"
        )) {
            try CLIParser.parse(args: [
                "--stdlib-library", "/tmp/KSwiftKStdlib.kklib",
                "--stdlib-from-source",
                "main.kt",
            ])
        }
    }

    @Test
    func rejectsStdlibOnlyWithInput() {
        #expect(throws: CLIParseError.incompatibleStdlibOptions("--stdlib-only cannot be combined with input files")) {
            try CLIParser.parse(args: ["--stdlib-only", "main.kt"])
        }
    }

    @Test
    func rejectsStdlibOnlyWithNonLibraryEmit() {
        #expect(throws: CLIParseError.stdlibOnlyRequiresLibraryEmit) {
            try CLIParser.parse(args: ["--stdlib-only", "--emit", "object"])
        }
        #expect(throws: CLIParseError.stdlibOnlyRequiresLibraryEmit) {
            try CLIParser.parse(args: ["--emit", "object", "--stdlib-only"])
        }
    }

    @Test
    func rejectsStdlibLibraryWithExplicitStdlib() {
        #expect(throws: CLIParseError.incompatibleStdlibOptions("--stdlib-library cannot be combined with --stdlib")) {
            try CLIParser.parse(args: ["--stdlib-library", "/tmp/KSwiftKStdlib.kklib", "--stdlib", "main.kt"])
        }
    }

    @Test
    func helpFlagRequestsUsage() {
        #expect(throws: CLIParseError.usageRequested) {
            try CLIParser.parse(args: ["--help"])
        }
    }
}
#endif
