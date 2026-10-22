#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func lambdasClosuresHigherOrderAndSharedMutation(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun apply(value: Int, operation: (Int) -> Int): Int = operation(value)
            fun counter(start: Int): () -> Int { var current = start; return { current += 1; current } }
            fun shared(): List<() -> Int> {
                var current = 0
                val next = { current += 1; current }
                val read = { current }
                return listOf(next, read)
            }
            fun main() {
                val scale = 3
                println(apply(14) { it * scale })
                val next = counter(8)
                println(next())
                println(next.invoke())
                val callbacks = shared()
                println(callbacks[0]())
                println(callbacks[1]())
                println(callbacks[0]())
                println(callbacks[1]())
                var outside = 10
                val change: (Int) -> Int = { n -> outside += n; outside }
                outside = 20
                println(change(22))
                println(outside)
                val nested: (Int) -> () -> Int = { x -> { x + scale } }
                println(nested(4)())
                val wide: (Long, Double) -> Double = { a, b -> a.toDouble() + b }
                println(wide(10L, 0.5))
            }
            """, expected: "42\n9\n10\n1\n1\n2\n2\n42\n42\n7\n10.5\n", mode: mode, root: root)
        }
    }
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func extensionFunctionsReceiverLambdasAndNestedReceivers(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            fun Int.twice(): Int = this * 2
            fun Int.withOperation(block: Int.() -> Int): Int = block()
            fun String?.orFallback(): String = if (this == null) "fallback" else this!!
            fun <T> T.pipe(block: (T) -> T): T = block(this)
            class Counter(var value: Int) {
                private fun add(n: Int): Int { value += n; return value }
                fun make(): (Int) -> Int = { n -> add(n) }
                fun Int.shift(): Int = this + value
                fun run(): Int = 2.shift()
            }
            class Outer(val n: Int) { fun score(): Int = n }
            class Inner
            class MemberPriority { fun pick(): Int = 5 }
            fun exercise(): Int {
                val f: Outer.() -> Int = outer@ {
                    val g: Inner.() -> Int = { score() + this@outer.n }
                    g(Inner())
                }
                return f(Outer(7))
            }
            fun main() {
                println(21.twice())
                println(20.withOperation { this + 22 })
                println((null as String?).orFallback())
                val c = Counter(1)
                val change = c.make()
                println(change(2))
                println(c.run())
                val receiver: Int.(Int) -> Int = { other -> this + other }
                println(20.receiver(22))
                println(exercise())
                println(21.pipe { it * 2 })
                val pick: MemberPriority.() -> Int = { 99 }
                println(MemberPriority().pick())
                val increment: Int.() -> Int = { this + 1 }
                val escaped = { 41.increment() }
                println(escaped())
                val outer: Int.() -> Int = {
                    val callback: Int.() -> Int = { this * 2 }
                    val inner: Inner.() -> Int = { callback() }
                    inner(Inner())
                }
                println(outer(21))
            }
            """, expected: "42\n42\nfallback\n3\n5\n42\n14\n42\n5\n42\n42\n", mode: mode, root: root)
        }
    }
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func collectionHigherOrderOperationsAndArrayInitializers(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                var total = 0
                val mapped = listOf(1, 2, 3).map { it * 2 }.filter { it > 2 }
                mapped.forEach { value -> if (value == 4) return@forEach; total += value }
                println(total)
                println(mapped.fold(10) { sum, value -> sum + value })
                val values = IntArray(3) { index -> index + 1 }
                println(values.fold(0) { sum, value -> sum + value })
                val words = Array<String>(2) { index -> if (index == 0) "first" else "second" }
                words.forEach { println(it) }
                val emit: (String) -> Unit = { println(it) }
                words.forEach(emit)
                val action: () -> Unit = { println("unit") }
                action()
                val square: (Int) -> Int = { it * it }
                val squared = values.map(square)
                println(squared[2])
            }
            """, expected: "6\n20\n6\nfirst\nsecond\nfirst\nsecond\nunit\n9\n", mode: mode, root: root)
        }
    }
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func closuresInMembersInterfacesAndConstructorArguments(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            open class Parent(val block: () -> Int) { fun result(): Int = block() }
            class Child(start: Int): Parent({ start + 1 })
            interface Source {
                fun base(): Int
                fun callback(): () -> Int = { base() }
            }
            class Impl: Source { override fun base(): Int = 11 }
            interface Extension<T> { fun T.score(): Int; fun run(value: T): Int = value.score() }
            class IntExtension: Extension<Int> { override fun Int.score(): Int = this * 2 }
            class Accessor {
                var value: Int = 7
                    get() { val read = { val nested = { field }; nested() }; return read() }
                    set(value) { val write = { val nested = { field = value }; nested() }; write() }
            }
            class Owner(private var number: Int) {
                private fun plus(value: Int): Int { number += value; return number }
                val callback: (Int) -> Int = { value -> plus(value) }
                fun action(): () -> Int = { number += 1; number }
            }
            fun main() {
                println(Child(41).result())
                println(Impl().callback()())
                val owner = Owner(10)
                println(owner.callback(2))
                println(owner.action()())
                val accessor = Accessor()
                println(accessor.value)
                accessor.value = 9
                println(accessor.value)
                val extension: Extension<Int> = IntExtension()
                println(extension.run(21))
            }
            """, expected: "42\n11\n12\n13\n7\n9\n42\n", mode: mode, root: root)
        }
    }
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func lambdaLocalReturnsAndExceptionsPreserveCapturedCells(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            fun operate(block: (Int) -> Int): Int = block(2)
            fun main() {
                var total = 0
                val change: (Int) -> Int = action@ { n ->
                    try {
                        total += n
                        if (n < 0) throw IllegalStateException("negative")
                        if (n == 0) return@action total
                        total
                    } finally { println("finally") }
                }
                println(change(3))
                try { change(-1) } catch(e: IllegalStateException) { println(e.message) }
                println(change(0))
                println(operate { value -> if (value == 2) return@operate 42; 0 })
                var index = 0
                val callbacks = mutableListOf<() -> Int>()
                for (i in 1..3) { callbacks.add { i } }
                while (index < callbacks.size) { println(callbacks[index]()); index++ }
            }
            """, expected: "finally\n3\nfinally\nnegative\nfinally\n2\n42\n1\n2\n3\n", mode: mode, root: root)
        }
    }

    @Test
    func functionTypesAndExtensionsAreCallableFromJavaAndOfficialKotlin() throws {
        try withWorkspace { root in
            let result = try compile("""
            package api
            fun apply(value: Int, operation: (Int) -> Int): Int = operation(value)
            fun counter(start: Int): () -> Int { var n = start; return { n += 1; n } }
            fun Int.plusOffset(other: Int): Int = this + other
            fun Int.withOperation(block: Int.() -> Int): Int = block()
            fun <T> T.pipe(block: (T) -> T): T = block(this)
            fun consume(action: (Int) -> Unit) { action(7) }
            fun action(): () -> Unit = { println("unit") }
            """, root: root, mode: .jvmJar)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            let jar = root.appendingPathComponent("hello.jar").path
            try """
            import kotlin.Unit;
            import kotlin.jvm.functions.Function0;
            import kotlin.jvm.functions.Function1;
            public class JavaConsumer {
                public static void main(String[] args) {
                    Function1<Integer, Integer> triple = x -> x * 3;
                    System.out.println(api.HelloKt.apply(14, triple));
                    Function0<Integer> next = api.HelloKt.counter(8);
                    System.out.println(next.invoke());
                    System.out.println(next.invoke());
                    System.out.println(api.HelloKt.plusOffset(20, 22));
                    System.out.println(api.HelloKt.withOperation(21, x -> x * 2));
                    System.out.println(api.HelloKt.pipe(21, triple));
                    api.HelloKt.consume(x -> { System.out.println(x); return Unit.INSTANCE; });
                    if (api.HelloKt.action().invoke() != Unit.INSTANCE) throw new AssertionError();
                }
            }
            """.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", jar, "JavaConsumer.java"], root: root)
            #expect(try java(["-cp", root.path + ":" + jar, "JavaConsumer"]).stdout == "42\n9\n10\n42\n42\n63\n7\nunit\n")
            try """
            import api.*
            fun main() {
                println(apply(operation = { it * 3 }, value = 14))
                val next: () -> Int = counter(8)
                println(next())
                println(next())
                println(20.plusOffset(other = 22))
                println(21.withOperation { this * 2 })
                println(21.pipe { it * 3 })
                consume { println(it) }
                val callback: () -> Unit = action()
                println(callback() == Unit)
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["Consumer.kt", "-cp", jar, "-include-runtime", "-d", "consumer.jar"], root: root)
            let consumer = root.appendingPathComponent("consumer.jar").path
            for classpath in [consumer + ":" + jar, jar + ":" + consumer] {
                #expect(try java(["-cp", classpath, "ConsumerKt"]).stdout == "42\n9\n10\n42\n42\n63\n7\nunit\ntrue\n")
            }
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func closuresPreserveLexicalBindingsAndCallableCaptures(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            fun later(callback: (Int) -> Int): () -> Int = { callback(21) }
            fun main() {
                val outer = 7
                val read = { outer }
                println(({ val outer = 100; read() + outer })())
                val typed = { left: Int, right: Int -> left + right }
                val callback = later { typed(it, it) }
                println(callback())
                var operation: ((Int) -> Int)? = null
                val replace = { operation = { it * 2 } }
                replace()
                println(operation!!(21))
                val callbacks = mutableListOf<() -> Int>()
                for (i in 1..3) {
                    var value = i
                    callbacks.add { value += 10; value }
                }
                println(callbacks[0]())
                println(callbacks[1]())
                println(callbacks[0]())
                val wide = 20L
                val decimal = 0.5
                println(({ wide + decimal })())
            }
            """, expected: "107\n42\n42\n11\n12\n21\n20.5\n", mode: mode, root: root)
        }
    }

    @Test
    func functionArityLimitIsCheckedBeforeOutput() throws {
        try withWorkspace { root in
            for arity in [22, 23] {
                let types = Array(repeating: "Int", count: arity).joined(separator: ", ")
                let parameters = (0..<arity).map { "p\($0)" }.joined(separator: ", ")
                let arguments = Array(repeating: "1", count: arity).joined(separator: ", ")
                let sum = (0..<arity).map { "p\($0)" }.joined(separator: " + ")
                let source = "fun main() { val f: (\(types)) -> Int = { \(parameters) -> \(sum) }; println(f(\(arguments))) }"
                let output = root.appendingPathComponent("hello.jar")
                try? FileManager.default.removeItem(at: output)
                let result = try compile(source, root: root, mode: .jvmJar)
                #expect(result.0 == (arity == 22 ? 0 : 1), "\(result.1.map(\.message))")
                if arity == 22, result.0 == 0 {
                    #expect(try java(["-jar", output.path]).stdout == "22\n")
                } else { #expect(!FileManager.default.fileExists(atPath: output.path)) }
            }
        }
    }

    @Test
    func unicodeCapturesKeepDistinctBindingsAndDeterministicJar() throws {
        try withWorkspace { root in
            let source = """
            fun main() {
                val `é` = 20
                val `e\u{0301}` = 22
                val callback = { `é` + `e\u{0301}` }
                println(callback())
            }
            """
            let output = root.appendingPathComponent("hello.jar")
            #expect(try compile(source, root: root, mode: .jvmJar).0 == 0)
            let first = try Data(contentsOf: output)
            #expect(try compile(source, root: root, mode: .jvmJar).0 == 0)
            #expect(try Data(contentsOf: output) == first)
            #expect(try java(["-jar", output.path]).stdout == "42\n")
        }
    }

    @Test(arguments: [
        "fun main() { val f: (Int) -> Int = { x -> x }; println(f(\"bad\")) }",
        "fun main() { val f: (Int) -> Int = { x, y -> x + y }; println(f(1)) }",
        "fun main() { val n = 0; val f = { n += 1 }; f() }",
        "fun take(block: () -> Int): Int = block(); fun bad(): Int = take { return 1 }",
        "fun main() { mapOf(\"a\" to 1).forEach { key, value -> println(value) } }",
    ])
    func rejectsUnsupportedOrInvalidM6ProgramsWithoutReplacingOutput(source: String) throws {
        try withWorkspace { root in
            let output = root.appendingPathComponent("hello.jar")
            let sentinel = Data("previous jar".utf8)
            try sentinel.write(to: output)
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 == 1, "\(source)")
            #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
            #expect(try Data(contentsOf: output) == sentinel)
        }
    }
}
#endif
