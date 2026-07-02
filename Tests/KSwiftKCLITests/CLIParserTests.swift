#if canImport(Testing)
@testable import CompilerCore
@testable import KSwiftKCLI
import Testing
import XCTest

@Suite("CLI.Parser")
struct CLIParserTests {
    @Test
    func parsesMinimalInput() throws {
        let options = try CLIParser.parse(args: ["input.kt"])
        #expect(options.inputs == ["input.kt"])
        #expect(options.outputPath == "./a.out")
        #expect(options.moduleName == "Main")
        #expect(options.emit == .executable)
    }

    @Test
    func parsesOptionsAndFlags() throws {
        let options = try CLIParser.parse(args: [
            "-o", "out.bin",
            "-m", "Demo",
            "--emit", "kir",
            "-O2",
            "-I", "include",
            "--stdlib", "kotlin-stdlib.kklib",
            "-L", "lib",
            "-l", "runtime",
            "--target", "x86_64-apple-macos",
            "-Xfrontend", "time-phases",
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
        XCTAssertTrue(options.includeStdlib)
        XCTAssertTrue(options.stdlibSearchPaths.contains("kotlin-stdlib.kklib"))
        #expect(options.libraryPaths == ["lib"])
        #expect(options.linkLibraries == ["runtime"])
        #expect(options.frontendFlags == ["time-phases"])
        #expect(options.irFlags == ["trace-lowering"])
        #expect(options.runtimeFlags == ["trace=true"])
        #expect(options.debugInfo)
        #expect(options.inputs == ["main.kt"])
        #expect(options.target.arch == "x86_64")
        #expect(options.target.vendor == "apple")
        #expect(options.target.os == "macos")
    }

    func testParsesNoStdlibFlag() throws {
        let options = try CLIParser.parse(args: ["--no-stdlib", "main.kt"])

        XCTAssertFalse(options.includeStdlib)
        XCTAssertEqual(options.effectiveSearchPaths, options.searchPaths)
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
    func helpFlagRequestsUsage() {
        #expect(throws: CLIParseError.usageRequested) {
            try CLIParser.parse(args: ["--help"])
        }
    }
}
#endif
