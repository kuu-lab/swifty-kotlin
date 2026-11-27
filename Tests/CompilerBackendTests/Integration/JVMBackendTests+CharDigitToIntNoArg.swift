#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func charDigitToIntNoArgMatchesKotlinStdlibAndBundledRuntime() throws {
        let runtime = try m11Runtime()
        let runtimeJars = runtime.split(separator: ":").map(String.init)
        let source = """
        fun main() {
            println('5'.digitToInt())
            println('f'.digitToInt(16))
            try {
                println('a'.digitToInt())
            } catch (error: IllegalArgumentException) {
                println("invalid digit")
            }
        }
        """
        let expectedOutput = """
        5
        15
        invalid digit

        """

        try withWorkspace { root in
            let bundledResult = try compile(source, root: root, mode: .jvmJar, includeJVMRuntime: true)
            try #require(bundledResult.0 == 0, "\(bundledResult.1.map(\.message))")
            let jar = root.appendingPathComponent("hello.jar").path
            let bundledExecution = try java(["-jar", jar])
            #expect(bundledExecution.stdout == expectedOutput)
            #expect(bundledExecution.stderr.isEmpty)

            let externalResult = try compile(source, root: root, mode: .jvmJar, classpath: runtimeJars)
            try #require(externalResult.0 == 0, "\(externalResult.1.map(\.message))")
            let externalExecution = try java(["-cp", jar + ":" + runtime, "HelloKt"])
            #expect(externalExecution.stdout == expectedOutput)
            #expect(externalExecution.stderr.isEmpty)

            let referenceBuild = try jvmTool("kotlinc", ["hello.kt", "-include-runtime", "-d", "reference.jar"], root: root)
            try #require(referenceBuild.exitCode == 0, "\(referenceBuild.stderr)")
            let reference = try java(["-jar", root.appendingPathComponent("reference.jar").path])
            #expect(reference.stdout == expectedOutput)
            #expect(reference.stderr.isEmpty)
        }
    }
}
#endif
