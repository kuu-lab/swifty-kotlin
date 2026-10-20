#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func arrayConstructorsInlineAndPreserveReifiedComponents(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent("arrayConstructorInlineAndReifiedContracts.kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent("arrayConstructorInlineAndReifiedContracts.out"), encoding: .utf8)
        try withWorkspace { root in
            try runM11(source, expected: expected, mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func arrayConstructorsRejectUnreifiedComponentsBeforeReplacingOutput(mode: EmitMode) throws {
        try withWorkspace { root in
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            if mode == .jvmClass { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
            let marker = mode == .jvmJar ? output : output.appendingPathComponent("marker")
            let original = Data("previous output".utf8)
            try original.write(to: marker)
            for source in [
                "fun <T> make(value: T): Array<T> = Array<T>(1) { value }",
                "inline fun invalid(init: (Int) -> Int): IntArray = IntArray(1, init)",
                "inline fun invalid(crossinline init: (Int) -> Int): IntArray = IntArray(1, init)",
                "inline fun invalid(init: (Int) -> Int): IntArray = IntArray(1, init)\nfun main() { invalid { return } }",
                "fun <T> make(value: Array<T>): Array<Array<T>> = Array<Array<T>>(1) { value }",
            ] {
                let result = try compile(source, root: root, mode: mode)
                #expect(result.0 != 0)
                #expect(result.1.contains { $0.code == "KSWIFTK-JVM-0001" })
                #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
                #expect(try Data(contentsOf: marker) == original)
                if mode == .jvmClass { #expect(try FileManager.default.contentsOfDirectory(atPath: output.path) == ["marker"]) }
            }
        }
    }

    @Test
    func officialKotlinInlinesArrayConstructorsAndEscapingFactories() throws {
        try withWorkspace { root in
            let producer = try compile("""
            package api
            inline fun <reified T> filled(value: T): Array<T> = Array<T>(2) { value }
            inline fun <reified T> factory(value: T): () -> Array<T> = { Array<T>(1) { value } }
            inline fun <reified T> nestedFactory(value: T): () -> Array<Array<T>> = { Array<Array<T>>(1) { Array<T>(1) { value } } }
            inline fun <reified T> initialize(size: Int, init: (Int) -> T): Array<T> = Array<T>(size) { init(it) }
            inline suspend fun <reified T> suspended(value: T): Array<T> = Array<T>(1) { value }
            """, root: root, mode: .jvmJar)
            try #require(producer.0 == 0, "\(producer.1.map(\.message))")
            let runtime = try m11Runtime(), artifact = root.appendingPathComponent("hello.jar").path
            try """
            package consumer
            import api.*
            import kotlin.coroutines.*
            fun early(): Int { initialize<Int>(2) { return 42 }; return 0 }
            suspend fun value(): String = "suspend"
            suspend fun main() {
                val strings: Array<String> = filled("text")
                println(strings.javaClass.name); println(strings[1])
                println(filled(7).javaClass.name)
                println(filled(arrayOf("nested")).javaClass.name)
                println(factory("escaped")().javaClass.name)
                println(factory<String?>(null)()[0])
                println(nestedFactory("nested")().javaClass.name)
                println(early())
                val resumed: Array<String> = initialize<String>(1) { value() }
                println(resumed[0]); println(resumed.javaClass.name)
                println(suspended("inline-suspend").javaClass.name)
            }
            """.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-cp", artifact + ":" + runtime, "-d", "consumer.jar"], root: root)
            let result = try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + artifact + ":" + runtime, "consumer.ConsumerKt"])
            #expect(result.stdout == "[Ljava.lang.String;\ntext\n[Ljava.lang.Integer;\n[[Ljava.lang.String;\n[Ljava.lang.String;\nnull\n[[Ljava.lang.String;\n42\nsuspend\n[Ljava.lang.String;\n[Ljava.lang.String;\n")
            #expect(result.stderr.isEmpty)
        }
    }

    @Test(arguments: [false, true])
    func everyFileFacadeUsesTopLevelValueReturnMangling(reversed: Bool) throws {
        try withWorkspace { root in
            var sources = [("First.kt", "package api\nfun first(): Int = 1\n"), ("Library.kt", """
            package api
            @JvmInline value class Meter(val value: Int)
            fun create(): Meter = Meter(42)
            fun unsigned(): UInt = 42u
            fun defaulted(value: Int = 3): Meter = Meter(value)
            val current: Meter = Meter(21)
            fun consume(value: Meter): Meter = value
            """)]
            if reversed { sources.reverse() }
            let producer = try m22Build(root: root, sources: sources, name: "api.jar")
            try #require(producer.1 == 0, "\(producer.2.map(\.message))")
            let runtime = try m11Runtime(), artifact = producer.0.path
            try """
            public class JavaConsumer {
                public static void main(String[] args) {
                    System.out.println(api.LibraryKt.create());
                    System.out.println(api.LibraryKt.getCurrent());
                    System.out.println(api.LibraryKt.unsigned());
                    System.out.println(api.LibraryKt.defaulted(5));
                }
            }
            """.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", artifact + ":" + runtime, "JavaConsumer.java"], root: root)
            let javaResult = try java(["-cp", root.path + ":" + artifact + ":" + runtime, "JavaConsumer"])
            #expect(javaResult.stdout == "42\n21\n42\n5\n")
            #expect(javaResult.stderr.isEmpty)
            try """
            package consumer
            import api.*
            fun main() {
                println(create().value); println(current.value); println(unsigned())
                println(defaulted().value); println(consume(Meter(8)).value)
            }
            """.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-cp", artifact + ":" + runtime, "-d", "consumer.jar"], root: root)
            let kotlinResult = try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + artifact + ":" + runtime, "consumer.ConsumerKt"])
            #expect(kotlinResult.stdout == "42\n21\n42\n3\n8\n")
            #expect(kotlinResult.stderr.isEmpty)
        }
    }
}
#endif
