#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct ExtensionPropertyCallbackInvocationTests {
    @Test func interfaceExtensionPropertyCallbackCompilesAtO2() throws {
        let source = """
        interface Provider {
            val Int.callback: () -> Int
            fun use(): Int = 2.callback()
        }
        class Concrete : Provider {
            override val Int.callback: () -> Int get() = { this + 20 }
        }
        fun main() {
            val provider: Provider = Concrete()
            provider.use()
        }
        """
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("extension-property-callback.kt").path
        let output = directory.appendingPathComponent("extension-property-callback.ll").path
        try source.write(toFile: input, atomically: true, encoding: .utf8)
        let result = makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "ExtensionPropertyCallbackInvocation",
            inputs: [input],
            outputPath: output,
            emit: .llvmIR,
            target: TargetTriple.hostDefault(),
            optLevel: .O2,
            includeStdlib: false,
            allowDefaultStdlibLibrary: false
        ))
        try assertCompilationSucceeded(result, context: "interface member extension property callback at O2")
        #expect(FileManager.default.fileExists(atPath: output))
    }
}
#endif
