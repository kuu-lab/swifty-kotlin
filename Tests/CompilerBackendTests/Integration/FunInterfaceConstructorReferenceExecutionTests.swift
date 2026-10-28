import Foundation
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct FunInterfaceConstructorReferenceExecutionTests {
    @Test(arguments: [true, false], [0, 2])
    func constructsAndInvokesFunInterface(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("fun-interface-constructor-reference.kt").path
        let output = directory.appendingPathComponent("fun-interface-constructor-reference").path
        try """
        import kotlin.reflect.KFunction

        fun interface KRunnable { fun run() }
        val kr = ::KRunnable

        fun box(): String {
            val ctor: (() -> Unit) -> KRunnable = ::KRunnable
            var called = false
            val value = ctor { called = true }
            value.run()
            return if (called) "OK" else "Fail"
        }

        fun main() {
            println(if (kr is KFunction<*>) box() else "Fail")
        }
        """.write(toFile: input, atomically: true, encoding: .utf8)

        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "FunInterfaceConstructorReference",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        )))

        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "OK\n")
    }

    @Test
    func samWrappersRegisterDefaultMembersAndAcceptFunctionsCastFromAny() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("fun-interface-default-members.kt").path
        let output = directory.appendingPathComponent("fun-interface-default-members").path
        try """
        fun interface Interface {
            fun foo()
            val value: String get() = helper()
            fun defaultValue(): String = helper()
            private fun helper(): String = "OK"
        }

        fun interface KRunnable { fun invoke() }

        fun invokeFromAny(value: Any?) {
            val function = value as () -> Unit
            KRunnable(function).invoke()
        }

        fun main() {
            val value = Interface {}
            println(value.value)
            println(value.defaultValue())

            var called = false
            val function: () -> Unit = { called = true }
            invokeFromAny(function)
            println(if (called) "OK" else "Fail")
        }
        """.write(toFile: input, atomically: true, encoding: .utf8)

        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "FunInterfaceDefaultMembers",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: 0)),
            stdlibLibraryPath: try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: true
        )))

        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "OK\nOK\nOK\n")
    }

    @Test
    func samConstructorDispatchesAfterFunctionCastFromAny() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("sam-constructor-function-cast-from-any.kt").path
        let output = directory.appendingPathComponent("sam-constructor-function-cast-from-any").path
        try """
        fun interface KR { fun invoke() }

        fun test(a: Any) {
            a as () -> Unit
            KR(a).invoke()
        }

        fun main() {
            var result = "Fail"
            test { result = "OK" }
            println(result)
        }
        """.write(toFile: input, atomically: true, encoding: .utf8)

        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "SamConstructorFunctionCastFromAny",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: 0)),
            stdlibLibraryPath: try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: true
        )))

        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "OK\n")
    }

    @Test
    func samConstructorDispatchesAfterNullableFunctionCastFromAny() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("sam-constructor-nullable-function-cast-from-any.kt").path
        let output = directory.appendingPathComponent("sam-constructor-nullable-function-cast-from-any").path
        try """
        fun interface KRunnable { fun invoke() }

        fun test(a: Any?) {
            a as () -> Unit
            KRunnable(a).invoke()
        }

        fun main() {
            var called = false
            test { called = true }
            println(if (called) "OK" else "Fail")
        }
        """.write(toFile: input, atomically: true, encoding: .utf8)

        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "SamConstructorNullableFunctionCastFromAny",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: 0)),
            stdlibLibraryPath: try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: true
        )))

        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "OK\n")
    }
}
