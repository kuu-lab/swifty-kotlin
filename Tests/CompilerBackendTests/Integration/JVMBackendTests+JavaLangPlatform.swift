#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func javaLangDefaultImportIllegalAccessError(mode: EmitMode) throws {
        try withWorkspace { root in
            let result = try compile("fun main() { throw IllegalAccessError() }", root: root, mode: mode)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution: CommandResult
            do {
                execution = try java(["-cp", output.path, "HelloKt"])
            } catch CommandRunnerError.nonZeroExit(let failed) {
                execution = failed
            }
            #expect(execution.exitCode != 0)
            #expect(execution.stderr.contains("java.lang.IllegalAccessError"))
            #expect(execution.stderr.contains("HelloKt.main(hello.kt)"))
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func javaLangConstantsExceptionsAndArraycopy(mode: EmitMode) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let result = try compile("""
            import java.lang.IllegalArgumentException
            fun main() {
                println(Math.PI); println(Math.E)
                val values = intArrayOf(1, 2, 3, 4)
                System.arraycopy(values, 0, values, 1, 3)
                println(values.joinToString())
                val objects = arrayOf("a", "b", "c")
                System.arraycopy(objects, 1, objects, 0, 2)
                println(objects.joinToString())
                try { System.arraycopy(null, 0, objects, 0, 0) }
                catch (e: NullPointerException) { println("null") }
                try { System.arraycopy(values, 0, values, 0, -1) }
                catch (e: IndexOutOfBoundsException) { println("bounds") }
                try { throw IllegalArgumentException("expected") }
                catch (e: kotlin.IllegalArgumentException) { println(e.message) }
            }
            """, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", output.path + ":" + library.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "3.141592653589793\n2.718281828459045\n1, 1, 2, 3\nb, c, c\nnull\nbounds\nexpected\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
