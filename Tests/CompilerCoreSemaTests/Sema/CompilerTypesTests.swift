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

    @Test(arguments: ["executable", "object", "llvmIR", "kirDump", "library"])
    func testDefaultStdlibArtifactPolicy(emitMode: String) throws {
        let emit = try #require(EmitMode(rawValue: emitMode))
        func applies(allow: Bool = true, include: Bool = true,
                     only: Bool = false, path: String? = nil) -> Bool {
            CompilerOptions.shouldUseDefaultStdlib(
                allowDefaultStdlibLibrary: allow,
                includeStdlib: include,
                stdlibOnly: only,
                stdlibLibraryPath: path,
                emit: emit
            )
        }
        #expect(applies())
        #expect(!applies(allow: false))
        #expect(!applies(include: false))
        #expect(!applies(only: true))
        #expect(!applies(path: "/tmp/explicit.kklib"))

        let sourceOptions = CompilerOptions(
            moduleName: "SourceFallback",
            inputs: ["main.kt"],
            outputPath: "out",
            emit: emit,
            target: .hostDefault(),
            allowDefaultStdlibLibrary: false
        )
        #expect(!sourceOptions.allowDefaultStdlibLibrary)
        #expect(sourceOptions.stdlibLibraryPath == nil)
        #expect(sourceOptions.includeStdlib)
    }
}
#endif
