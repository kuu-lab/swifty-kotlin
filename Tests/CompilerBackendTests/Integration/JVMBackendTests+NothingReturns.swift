#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func ownStdlibNothingReturnsKeepControlFlowAndNullableObjectBoundary(mode: EmitMode) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let result = try compile("""
            fun <T> identity(value: T): T = value
            fun <T : Any> nullableBound(value: T?): T? = value
            fun recovered(value: String?): String = value ?: error("elvis")
            fun branch(value: Boolean): Int = if (value) 7 else error("branch")
            fun returned(): Int { return error("return") }
            fun never(value: Boolean): Nothing {
                if (value) throw IllegalStateException("throw")
                else error("tail")
            }
            fun <T : Nothing> upperFailure(): T = error("upper")
            fun <T> invokeFactory(block: () -> T): T = block()
            fun unitBlock() { println("unit") }
            fun main() {
                println(recovered("ok"))
                println(branch(true))
                val empty: Nothing? = null
                val erased: Any? = empty
                println(erased == null)
                println(identity<Nothing?>(null) == null)
                println(nullableBound<Nothing>(null) == null)
                unitBlock()
                try { recovered(null) }
                catch (failure: IllegalStateException) { println(failure.message) }
                try { branch(false) }
                catch (failure: IllegalStateException) { println(failure.message) }
                try { returned() }
                catch (failure: IllegalStateException) { println(failure.message) }
                try { never(true) }
                catch (failure: IllegalStateException) { println(failure.message) }
                try { never(false) }
                catch (failure: IllegalStateException) { println(failure.message) }
                val callback: () -> Nothing = { error("lambda") }
                try { callback() }
                catch (failure: IllegalStateException) { println(failure.message) }
                try { upperFailure<Nothing>() }
                catch (failure: IllegalStateException) { println(failure.message) }
                try { invokeFactory<Nothing> { error("lower") } }
                catch (failure: IllegalStateException) { println(failure.message) }
            }
            """, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let data: Data
            if mode == .jvmJar {
                let archive = try ZipArchive(data: Data(contentsOf: artifact))
                let entry = try #require(archive.entries.first { $0.name == "HelloKt.class" })
                data = Data(try archive.contents(of: entry))
            } else {
                data = try Data(contentsOf: artifact.appendingPathComponent("HelloKt.class"))
            }
            var reader = JVMClassReader(bytes: Array(data))
            let owner = try reader.read()
            #expect(owner.methods.contains { $0.name == "never" && $0.descriptor == "(Z)Ljava/lang/Void;" })
            #expect(owner.methods.contains { $0.name == "unitBlock" && $0.descriptor == "()V" })
            let execution = try java(["-cp", artifact.path + ":" + library.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "ok\n7\ntrue\ntrue\ntrue\nunit\nelvis\nbranch\nreturn\nthrow\ntail\nlambda\nupper\nlower\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test
    func ownStdlibNothingReturnsExposeDedicatedExceptionConstructors() throws {
        let library = try ownStdlibLibrary()
        let archive = try ZipArchive(data: Data(contentsOf: library))
        let entry = try #require(archive.entries.first { $0.name == "kotlin/KotlinNothingValueException.class" })
        var reader = JVMClassReader(bytes: Array(try archive.contents(of: entry)))
        let owner = try reader.read()
        #expect(owner.superclass == "java/lang/RuntimeException")
        #expect(Set(owner.methods.filter { $0.name == "<init>" }.map(\.descriptor)) == Set([
            "()V", "(Ljava/lang/String;)V", "(Ljava/lang/String;Ljava/lang/Throwable;)V", "(Ljava/lang/Throwable;)V",
        ]))
        try withWorkspace { root in
            try """
            public class NothingExceptionConsumer {
                public static void main(String[] args) {
                    Throwable cause = new IllegalStateException("cause");
                    System.out.println(new kotlin.KotlinNothingValueException().getMessage() == null);
                    System.out.println(new kotlin.KotlinNothingValueException("message").getMessage());
                    kotlin.KotlinNothingValueException combined = new kotlin.KotlinNothingValueException("both", cause);
                    System.out.println(combined.getMessage()); System.out.println(combined.getCause() == cause);
                    kotlin.KotlinNothingValueException caused = new kotlin.KotlinNothingValueException(cause);
                    System.out.println(caused.getMessage()); System.out.println(caused.getCause() == cause);
                }
            }
            """.write(to: root.appendingPathComponent("NothingExceptionConsumer.java"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("javac", ["-classpath", library.path, "NothingExceptionConsumer.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let execution = try java(["-cp", root.path + ":" + library.path, "NothingExceptionConsumer"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "true\nmessage\nboth\ntrue\njava.lang.IllegalStateException: cause\ntrue\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test(arguments: [
        "fun value(): Nothing? = null; fun main() { println(value()) }",
        "fun value(input: Nothing) {}; fun main() {}",
        "fun value(input: Nothing?) {}; fun main() { value(null) }",
        "val value: Nothing? = null; fun main() { println(value) }",
        "fun Nothing.value(): Int = 1; fun main() {}",
    ])
    func ownStdlibNothingReturnsPreserveUnsupportedPublicTypeBoundaries(source: String) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: .jvmJar, classpath: [library.path])
            #expect(result.0 != 0)
            #expect(result.1.contains { $0.code == "KSWIFTK-JVM-0001" })
        }
    }
}
#endif
