#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct NativePlatformInfoExecutionTests {
    @Test
    func reportsNativePlatformInfoForHost() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = repositoryRoot.appendingPathComponent(
            "Tests/CompilerBackendTests/Fixtures/native-platform/platform_info.kt"
        )
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("NativePlatformInfo-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: outputBase) }

        let context = makeCompilationContext(
            inputs: [fixture.path],
            moduleName: "NativePlatformInfo",
            emit: .executable,
            outputPath: outputBase
        )
        #expect(
            context.options.target.arch == Self.expectedHostTargetArchitecture,
            "The Kotlin fixture must compile for this Swift test process's native architecture"
        )
        #expect(
            context.options.target.os == Self.expectedHostTargetOS,
            "The Kotlin fixture must compile for this Swift test process's native OS"
        )

        try runToKIR(context)
        #expect(!context.diagnostics.hasError, "Native platform fixture should compile without errors")
        try LoweringPhase().run(context)
        try CodegenPhase().run(context)
        try LinkPhase().run(context)

        let processorOverrideKey = "KOTLIN_NATIVE_AVAILABLE_PROCESSORS"
        let originalProcessorOverride = ProcessInfo.processInfo.environment[processorOverrideKey]
        let originalWorkingDirectory = FileManager.default.currentDirectoryPath
        var childEnvironment = ProcessInfo.processInfo.environment
        childEnvironment[processorOverrideKey] = "3"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: outputBase)
        process.arguments = []
        process.environment = childEnvironment
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        #expect(
            ProcessInfo.processInfo.environment[processorOverrideKey] == originalProcessorOverride,
            "The processor override must be set only on the child process"
        )
        #expect(
            FileManager.default.currentDirectoryPath == originalWorkingDirectory,
            "Running the fixture must not change the test process working directory"
        )
        #expect(process.terminationStatus == 0, "Native platform executable failed: \(stderr)")

        let expectedOutput = [
            "unaligned=\(Self.expectedCanAccessUnaligned)",
            "little=\(Self.expectedIsLittleEndian)",
            "os=\(Self.expectedOsFamily)",
            "arch=\(Self.expectedCpuArchitecture)",
            "cpus=3",
        ].joined(separator: "\n") + "\n"
        #expect(stdout == expectedOutput, "Expected exact native platform output:\n\(expectedOutput)Got:\n\(stdout)")
    }

    private static var expectedHostTargetArchitecture: String {
#if arch(arm64)
#if os(Linux)
        "aarch64"
#else
        "arm64"
#endif
#elseif arch(x86_64)
        "x86_64"
#else
        "unsupported"
#endif
    }

    private static var expectedHostTargetOS: String {
#if os(macOS)
        "macosx"
#elseif os(Linux)
        "linux-gnu"
#else
        "unsupported"
#endif
    }

    private static var expectedCanAccessUnaligned: Bool {
#if arch(x86_64) || arch(i386) || arch(arm64)
        true
#else
        false
#endif
    }

    private static var expectedIsLittleEndian: Bool {
        var value: UInt32 = 0x0102_0304
        return withUnsafeBytes(of: &value) { bytes in
            bytes.first == 0x04
        }
    }

    private static var expectedOsFamily: String {
#if os(macOS)
        "MACOSX"
#elseif os(iOS)
        "IOS"
#elseif os(tvOS)
        "TVOS"
#elseif os(watchOS)
        "WATCHOS"
#elseif os(Linux)
        "LINUX"
#elseif os(Windows)
        "WINDOWS"
#elseif os(Android)
        "ANDROID"
#elseif os(WASI)
        "WASM"
#else
        "UNKNOWN"
#endif
    }

    private static var expectedCpuArchitecture: String {
#if arch(x86_64)
        "X64"
#elseif arch(i386)
        "X86"
#elseif arch(arm64)
        "ARM64"
#elseif arch(arm)
        "ARM32"
#elseif arch(wasm32)
        "WASM32"
#else
        "UNKNOWN"
#endif
    }
}
#endif
