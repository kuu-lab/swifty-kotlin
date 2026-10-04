#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CompilerTypesTests {

    @Test func testTargetTripleWithNilOsVersion() {
        let triple = TargetTriple(arch: "x86_64", vendor: "unknown", os: "linux", osVersion: nil)
        #expect(triple.arch == "x86_64")
        #expect(triple.vendor == "unknown")
        #expect(triple.os == "linux")
        #expect(triple.osVersion == nil)
    }

    @Test func testCompilerOptionsDebugInfoPropertyGetAndSet() {
        let target = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        var options = CompilerOptions(
            moduleName: "M",
            inputs: ["a.kt"],
            outputPath: "out",
            emit: .object,
            target: target,
            debugInfo: false
        )
        #expect(!(options.debugInfo))
        options.debugInfo = true
        #expect(options.debugInfo)
    }

    @Test func testInitWithDebugInfo() {
        let target = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        let options = CompilerOptions(
            moduleName: "ModuleWithDebug",
            inputs: ["b.kt"],
            outputPath: "out2",
            emit: .executable,
            searchPaths: ["/sp"],
            libraryPaths: ["/lp"],
            linkLibraries: ["z"],
            target: target,
            optLevel: .O2,
            debugInfo: true,
            frontendFlags: ["-Xf"],
            irFlags: ["-Xi"],
            runtimeFlags: ["-Xr"]
        )
        #expect(options.moduleName == "ModuleWithDebug")
        #expect(options.inputs == ["b.kt"])
        #expect(options.outputPath == "out2")
        #expect(options.emit == .executable)
        #expect(options.searchPaths == ["/sp"])
        #expect(options.libraryPaths == ["/lp"])
        #expect(options.linkLibraries == ["z"])
        #expect(options.target == target)
        #expect(options.optLevel == .O2)
        #expect(options.debugInfo)
        #expect(options.frontendFlags == ["-Xf"])
        #expect(options.irFlags == ["-Xi"])
        #expect(options.runtimeFlags == ["-Xr"])
    }

    @Test func testHostDefaultTargetTripleMatchesCompileArchitecture() {
        let host = TargetTriple.hostDefault()
        #if os(Linux) && arch(arm64)
            #expect(host.arch == "aarch64")
        #elseif arch(arm64)
            #expect(host.arch == "arm64")
        #elseif arch(x86_64)
            #expect(host.arch == "x86_64")
        #endif
        #if os(Linux)
            #expect(host.vendor == "unknown")
            #expect(host.os == "linux-gnu")
        #else
            #expect(host.vendor == "apple")
            #expect(host.os == "macosx")
        #endif
        #expect(host.osVersion == nil)
    }

    @Test func testDefaultStdlibArtifactIsExecutableOnlyAndOptOutIsExplicit() {
        let common = TargetTriple.hostDefault()

        #expect(
            CompilerOptions.shouldUseDefaultStdlib(
                allowDefaultStdlibLibrary: true,
                includeStdlib: true,
                stdlibOnly: false,
                stdlibLibraryPath: nil,
                emit: .executable
            )
        )
        #expect(
            !CompilerOptions.shouldUseDefaultStdlib(
                allowDefaultStdlibLibrary: true,
                includeStdlib: true,
                stdlibOnly: false,
                stdlibLibraryPath: nil,
                emit: .kirDump
            )
        )
        #expect(
            !CompilerOptions.shouldUseDefaultStdlib(
                allowDefaultStdlibLibrary: false,
                includeStdlib: true,
                stdlibOnly: false,
                stdlibLibraryPath: nil,
                emit: .executable
            )
        )

        let sourceOptions = CompilerOptions(
            moduleName: "SourceFallback",
            inputs: ["main.kt"],
            outputPath: "out",
            emit: .executable,
            target: common,
            allowDefaultStdlibLibrary: false
        )
        #expect(sourceOptions.allowDefaultStdlibLibrary == false)
        #expect(sourceOptions.stdlibLibraryPath == nil)
        #expect(sourceOptions.includeStdlib)
    }
}
#endif
