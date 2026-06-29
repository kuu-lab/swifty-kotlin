#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CompilerTypesTests {
    @Test func testTargetTripleStoreValues() {
        let triple = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: "14.0")
        #expect(triple.arch == "arm64")
        #expect(triple.vendor == "apple")
        #expect(triple.os == "macosx")
        #expect(triple.osVersion == "14.0")
    }

    @Test func testCompilerOptionsDefaultArguments() {
        let options = CompilerOptions(
            moduleName: "DefaultModule",
            inputs: ["input.kt"],
            outputPath: "out.o",
            emit: .object,
            target: TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        )

        #expect(options.moduleName == "DefaultModule")
        #expect(options.inputs == ["input.kt"])
        #expect(options.outputPath == "out.o")
        #expect(options.emit == .object)
        #expect(options.searchPaths == [])
        #expect(options.libraryPaths == [])
        #expect(options.linkLibraries == [])
        #expect(options.optLevel == .O0)
        #expect(!(options.debugInfo))
        #expect(options.frontendFlags == [])
        #expect(options.irFlags == [])
        #expect(options.runtimeFlags == [])
    }

    @Test func testCompilerOptionsDebugInfoPropertyAndInit() {
        let target = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)

        var options = CompilerOptions(
            moduleName: "M",
            inputs: ["a.kt"],
            outputPath: "out",
            emit: .executable,
            target: target,
            debugInfo: true
        )
        #expect(options.debugInfo)

        options.debugInfo = false
        #expect(!(options.debugInfo))
    }

    @Test func testCompilerOptionsCustomArgumentsAndEnums() {
        let target = TargetTriple(arch: "x86_64", vendor: "pc", os: "linux", osVersion: "6")
        let options = CompilerOptions(
            moduleName: "CustomModule",
            inputs: ["a.kt", "b.kt"],
            outputPath: "bin/custom",
            emit: .library,
            searchPaths: ["/opt/include"],
            libraryPaths: ["/opt/lib"],
            linkLibraries: ["m", "pthread"],
            target: target,
            optLevel: .O3,
            debugInfo: true,
            frontendFlags: ["-XfrontendA"],
            irFlags: ["-XirA"],
            runtimeFlags: ["-XruntimeA"]
        )

        #expect(options.target == target)
        #expect(options.optLevel == .O3)
        #expect(options.debugInfo)
        #expect(options.searchPaths == ["/opt/include"])
        #expect(options.libraryPaths == ["/opt/lib"])
        #expect(options.linkLibraries == ["m", "pthread"])
        #expect(options.frontendFlags == ["-XfrontendA"])
        #expect(options.irFlags == ["-XirA"])
        #expect(options.runtimeFlags == ["-XruntimeA"])
    }

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

    @Test func testInitWithDebugInfoDefaultArguments() {
        let options = CompilerOptions(
            moduleName: "M2",
            inputs: ["b.kt"],
            outputPath: "out2",
            emit: .llvmIR,
            target: TargetTriple(arch: "x86_64", vendor: "pc", os: "linux", osVersion: nil),
            debugInfo: false
        )
        #expect(options.moduleName == "M2")
        #expect(options.emit == .llvmIR)
        #expect(!(options.debugInfo))
        #expect(options.searchPaths == [])
        #expect(options.libraryPaths == [])
        #expect(options.linkLibraries == [])
        #expect(options.optLevel == .O0)
        #expect(options.frontendFlags == [])
        #expect(options.irFlags == [])
        #expect(options.runtimeFlags == [])
    }

    @Test func testOptimizationLevelEquality() {
        #expect(OptimizationLevel.O0 != OptimizationLevel.O3)
    }

    @Test func testTargetTripleEquality() {
        let t1 = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: "14.0")
        let t2 = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: "14.0")
        let t3 = TargetTriple(arch: "x86_64", vendor: "apple", os: "macosx", osVersion: "14.0")
        #expect(t1 == t2)
        #expect(t1 != t3)
    }

    @Test func testCompilerOptionsEquality() {
        let target = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        let o1 = CompilerOptions(
            moduleName: "M", inputs: ["a.kt"], outputPath: "out",
            emit: .object, target: target
        )
        let o2 = CompilerOptions(
            moduleName: "M", inputs: ["a.kt"], outputPath: "out",
            emit: .object, target: target
        )
        let o3 = CompilerOptions(
            moduleName: "N", inputs: ["a.kt"], outputPath: "out",
            emit: .object, target: target
        )
        #expect(o1 == o2)
        #expect(o1 != o3)
    }

    @Test func testHostDefaultTargetTripleMatchesCompileArchitecture() {
        let host = TargetTriple.hostDefault()
        #if arch(arm64)
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
}
#endif
