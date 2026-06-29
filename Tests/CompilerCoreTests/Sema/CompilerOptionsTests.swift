#if canImport(Testing)
@testable import CompilerCore
import Testing
import XCTest

@Suite
struct CompilerOptionsTests {
    // MARK: - TargetTriple

    @Test func testTargetTripleInit() {
        let triple = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: "14.0")
        #expect(triple.arch == "arm64")
        #expect(triple.vendor == "apple")
        #expect(triple.os == "macosx")
        #expect(triple.osVersion == "14.0")
    }

    @Test func testTargetTripleEquatable() {
        let t1 = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        let t2 = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        let t3 = TargetTriple(arch: "x86_64", vendor: "apple", os: "macosx", osVersion: nil)
        #expect(t1 == t2)
        #expect(t1 != t3)
    }

    @Test func testTargetTripleHostDefault() {
        let triple = TargetTriple.hostDefault()
        #expect(!(triple.arch.isEmpty))
        #expect(!(triple.vendor.isEmpty))
        #expect(!(triple.os.isEmpty))
    }

    @Test func testTargetTripleWithNilOsVersion() {
        let triple = TargetTriple(arch: "arm64", vendor: "unknown", os: "linux-gnu", osVersion: nil)
        #expect(triple.osVersion == nil)
    }

    // MARK: - CompilerOptions init

    @Test func testCompilerOptionsDefaultValues() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: ["/a.kt"],
            outputPath: "/out",
            emit: .executable,
            target: defaultTargetTriple()
        )
        #expect(opts.moduleName == "Test")
        #expect(opts.inputs == ["/a.kt"])
        #expect(opts.outputPath == "/out")
        XCTAssertTrue(opts.stdlibSearchPaths.isEmpty)
        XCTAssertTrue(opts.includeStdlib)
        XCTAssertTrue(opts.effectiveSearchPaths.isEmpty)
        #expect(opts.emit == .executable)
        #expect(opts.searchPaths.isEmpty)
        #expect(opts.libraryPaths.isEmpty)
        #expect(opts.linkLibraries.isEmpty)
        #expect(opts.optLevel == .O0)
        #expect(!(opts.debugInfo))
        #expect(opts.frontendFlags.isEmpty)
        #expect(opts.irFlags.isEmpty)
        #expect(opts.runtimeFlags.isEmpty)
        #expect(opts.incrementalCachePath == nil)
    }

    @Test func testCompilerOptionsWithAllFields() {
        let opts = CompilerOptions(
            moduleName: "MyMod",
            inputs: ["/a.kt", "/b.kt"],
            outputPath: "/out/bin",
            emit: .object,
            searchPaths: ["/lib"],
            stdlibSearchPaths: ["/stdlib"],
            libraryPaths: ["/ext"],
            linkLibraries: ["runtime"],
            target: TargetTriple(arch: "x86_64", vendor: "unknown", os: "linux-gnu", osVersion: nil),
            optLevel: .O2,
            debugInfo: true,
            frontendFlags: ["jobs=4"],
            irFlags: ["opt-passes"],
            runtimeFlags: ["gc=conservative"],
            incrementalCachePath: "/cache"
        )
        #expect(opts.moduleName == "MyMod")
        #expect(opts.inputs.count == 2)
        #expect(opts.emit == .object)
        #expect(opts.searchPaths == ["/lib"])
        XCTAssertEqual(opts.stdlibSearchPaths, ["/stdlib"])
        XCTAssertEqual(opts.effectiveSearchPaths, ["/stdlib", "/lib"])
        #expect(opts.libraryPaths == ["/ext"])
        #expect(opts.linkLibraries == ["runtime"])
        #expect(opts.optLevel == .O2)
        #expect(opts.debugInfo)
        #expect(opts.frontendFlags == ["jobs=4"])
        #expect(opts.irFlags == ["opt-passes"])
        #expect(opts.runtimeFlags == ["gc=conservative"])
        #expect(opts.incrementalCachePath == "/cache")
        #expect(!(opts.includeNonPublicReflectionMetadata))
    }

    @Test func testCompilerOptionsRuntimeMetadataVisibilityFlag() {
        let opts = CompilerOptions(
            moduleName: "MyMod",
            inputs: ["/a.kt"],
            outputPath: "/out/bin",
            emit: .object,
            target: defaultTargetTriple(),
            runtimeFlags: ["reflection-metadata=all"]
        )

        #expect(opts.includeNonPublicReflectionMetadata)
    }

    @Test func testCompilerOptionsEquatable() {
        let opts1 = CompilerOptions(
            moduleName: "A",
            inputs: ["/a.kt"],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let opts2 = CompilerOptions(
            moduleName: "A",
            inputs: ["/a.kt"],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let opts3 = CompilerOptions(
            moduleName: "B",
            inputs: ["/a.kt"],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        #expect(opts1 == opts2)
        #expect(opts1 != opts3)
    }

    // MARK: - frontendJobs

    @Test func testFrontendJobsDefaultIsOne() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        #expect(opts.frontendJobs == 1)
    }

    @Test func testFrontendJobsParsesFromFlag() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple(),
            frontendFlags: ["jobs=8"]
        )
        #expect(opts.frontendJobs == 8)
    }

    @Test func testFrontendJobsIgnoresInvalidValues() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple(),
            frontendFlags: ["jobs=0"]
        )
        // jobs=0 is < 1, so should return default of 1
        #expect(opts.frontendJobs == 1)
    }

    @Test func testFrontendJobsIgnoresNonNumeric() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple(),
            frontendFlags: ["jobs=abc"]
        )
        #expect(opts.frontendJobs == 1)
    }

    @Test func testFrontendJobsIgnoresUnrelatedFlags() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple(),
            frontendFlags: ["sema-cache", "debug-mode"]
        )
        #expect(opts.frontendJobs == 1)
    }

    @Test func testFrontendJobsUsesFirstMatch() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple(),
            frontendFlags: ["jobs=4", "jobs=8"]
        )
        #expect(opts.frontendJobs == 4)
    }

    // MARK: - lazyThreadSafetyMode

    @Test func testLazyThreadSafetyModeDefaultIsSynchronized() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        #expect(opts.lazyThreadSafetyMode == .synchronized)
    }

    @Test func testLazyThreadSafetyModeNone() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple(),
            frontendFlags: ["lazy-thread-safety=NONE"]
        )
        #expect(opts.lazyThreadSafetyMode == .none)
    }

    @Test func testLazyThreadSafetyModeSynchronized() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple(),
            frontendFlags: ["lazy-thread-safety=SYNCHRONIZED"]
        )
        #expect(opts.lazyThreadSafetyMode == .synchronized)
    }

    @Test func testLazyThreadSafetyModePublication() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple(),
            frontendFlags: ["lazy-thread-safety=PUBLICATION"]
        )
        #expect(opts.lazyThreadSafetyMode == .publication)
    }

    @Test func testLazyThreadSafetyModeIsCaseInsensitive() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple(),
            frontendFlags: ["lazy-thread-safety=none"]
        )
        #expect(opts.lazyThreadSafetyMode == .none)
    }

    @Test func testLazyThreadSafetyModeUnknownValueDefaultsSynchronized() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple(),
            frontendFlags: ["lazy-thread-safety=UNKNOWN"]
        )
        #expect(opts.lazyThreadSafetyMode == .synchronized)
    }

    @Test func testAdvancedTypeInferenceFlagsAreDetected() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple(),
            frontendFlags: [
                "new-inference",
                "unrestricted-builder-inference",
                "ProperTypeInferenceConstraintsProcessing",
            ]
        )

        #expect(opts.useNewInference)
        #expect(opts.useUnrestrictedBuilderInference)
        #expect(opts.useProperTypeInferenceConstraintsProcessing)
    }

    // MARK: - EmitMode

    @Test func testEmitModeRawValues() {
        #expect(EmitMode.executable.rawValue == "executable")
        #expect(EmitMode.object.rawValue == "object")
        #expect(EmitMode.llvmIR.rawValue == "llvmIR")
        #expect(EmitMode.kirDump.rawValue == "kirDump")
        #expect(EmitMode.library.rawValue == "library")
    }

    // MARK: - OptimizationLevel

    @Test func testOptimizationLevelRawValues() {
        #expect(OptimizationLevel.O0.rawValue == 0)
        #expect(OptimizationLevel.O1.rawValue == 1)
        #expect(OptimizationLevel.O2.rawValue == 2)
        #expect(OptimizationLevel.O3.rawValue == 3)
    }

    // MARK: - LazyDelegateThreadSafetyMode

    @Test func testLazyDelegateThreadSafetyModeRawValues() {
        #expect(LazyDelegateThreadSafetyMode.synchronized.rawValue == 1)
        #expect(LazyDelegateThreadSafetyMode.none.rawValue == 0)
        #expect(LazyDelegateThreadSafetyMode.publication.rawValue == 2)
    }

}
#endif
