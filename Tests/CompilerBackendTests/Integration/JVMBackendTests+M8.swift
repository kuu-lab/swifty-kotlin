#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func singletonAndEnumInitializationFailuresAreCachedByJVM(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            object Log { var attempts = 0 }
            object Failed {
                init { Log.attempts++; throw IllegalStateException("failed") }
                fun value(): Int = 1
            }
            enum class Broken { VALUE { init { Log.attempts++; throw IllegalStateException("entry") } } }
            fun main() {
                for (i in 1..2) {
                    try { println(Failed.value()) } catch (failure: Throwable) { println(Log.attempts) }
                }
                for (i in 1..2) {
                    try { println(Broken.VALUE) } catch (failure: Throwable) { println(Log.attempts) }
                }
            }
            """, expected: "1\n1\n2\n2\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func objectsInheritClassesAndInterfaces(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            interface Provider {
                fun get(): Int
                companion object { fun answer(): Int = 42 }
            }
            open class Base(protected val n: Int) { init { println("base") }; open fun value(): Int = n }
            object Answer: Base(20), Provider {
                init { println("answer") }
                override fun value(): Int = n + 22
                override fun get(): Int = value()
            }
            fun main() { println(Answer.get()); println(Answer.value()); println(Provider.answer()) }
            """, expected: "base\nanswer\n42\n42\n42\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func objectsCompanionsInitializationAndPrivateAccess(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            object Counter {
                var value = 1
                val self = Counter
                val delayed: Int
                init { println("counter"); value += 1; delayed = 42 }
                fun add(n: Int): Int { value += n; return value }
            }
            class Factory private constructor(private val value: Int) {
                private fun read(): Int = value
                companion object Named {
                    private val offset: Int
                    init { offset = 20 }
                    fun create(n: Int): Factory = Factory(n + offset)
                    fun read(factory: Factory): Int = factory.read()
                }
            }
            fun main() {
                println(Counter.add(40))
                println(Counter.value)
                println(Counter.delayed)
                println(Counter == Counter.self)
                println(Factory.read(Factory.create(22)))
                println(Factory.Named.read(Factory.create(1)))
            }
            """, expected: "counter\n42\n42\n42\ntrue\n42\n21\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func dataClassesComponentsCopyEqualityAndFormatting(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            data class Point(val x: Int, var label: String) { var ignored = 0 }
            data class Box<T>(val value: T)
            data class Samples(val value: Double, val flags: IntArray)
            data class Number(val value: Double)
            data class Custom(val value: Int) { override fun toString(): String = "custom"; override fun hashCode(): Int = 7 }
            fun main() {
                val first = Point(21, "left")
                println(first)
                println(first.component1())
                println(first.copy(x = 42))
                println(first.copy())
                val other = Point(21, "left")
                other.ignored = 9
                println(first == other)
                println(first.hashCode() == other.hashCode())
                val (x, label) = first
                println(x); println(label)
                println(Box("generic").copy().value)
                val array = intArrayOf(1, 2)
                println(Samples(0.5, array))
                println(Samples(0.5, array) == Samples(0.5, array))
                println(Samples(0.5, array) == Samples(0.5, intArrayOf(1, 2)))
                val nan = 0.0 / 0.0
                println(Number(nan) == Number(nan))
                println(Number(-0.0) == Number(0.0))
                println(Custom(1).copy())
                println(Custom(1).hashCode())
            }
            """, expected: "Point(x=21, label=left)\n21\nPoint(x=42, label=left)\nPoint(x=21, label=left)\ntrue\ntrue\n21\nleft\ngeneric\nSamples(value=0.5, flags=[1, 2])\ntrue\nfalse\ntrue\nfalse\ncustom\n7\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func enumsEntriesValuesAndConstantBodies(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            enum class Mode(val code: Int) {
                FIRST(20) { override fun result(): Int = code * 2 },
                SECOND(22) { override fun result(): Int = code + 20 };
                abstract fun result(): Int
                companion object { fun total(): Int = FIRST.code + SECOND.code }
            }
            enum class Flag { ON { override val value: Int = 42 }; abstract val value: Int }
            enum class Empty { ; abstract fun unused(): Int }
            fun main() {
                println(Mode.FIRST.name)
                println(Mode.SECOND.ordinal)
                println(Mode.FIRST.result())
                println(Mode.valueOf("SECOND").result())
                println(Mode.total())
                val values = Mode.values()
                values[0] = Mode.SECOND
                println(Mode.values()[0].name)
                println(Mode.entries.size)
                println(Mode.entries[1].name)
                for (mode in Mode.entries) { println(mode.code) }
                try { Mode.valueOf("missing") } catch (error: IllegalArgumentException) { println("missing") }
                println(Flag.ON.value)
                println(Empty.values().size)
            }
            """, expected: "FIRST\n1\n40\n42\n42\nFIRST\n2\nSECOND\n20\n22\nmissing\n42\n0\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func sealedClassesNestedDataAndExhaustiveWhen(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            sealed class Shape {
                data class Circle(val radius: Int): Shape()
                object Empty: Shape()
            }
            fun area(shape: Shape): Int = when (shape) {
                is Shape.Circle -> shape.radius * 2
                Shape.Empty -> 0
            }
            sealed interface Outcome
            object Done: Outcome
            fun result(outcome: Outcome): Int = when (outcome) { Done -> 42 }
            fun classify(value: Any?): Int = when (value) { is Int -> 1; is String? -> 2; else -> 3 }
            fun main() {
                println(area(Shape.Circle(21)))
                println(area(Shape.Empty))
                println(Shape.Circle(2).copy(radius = 3))
                val shape: Shape? = null
                println(when (shape) { null -> 7; is Shape.Circle -> 8; Shape.Empty -> 9 })
                println(classify(42)); println(classify(null)); println(classify(false))
                println(result(Done))
            }
            """, expected: "42\n0\nCircle(radius=3)\n7\n1\n2\n3\n42\n", mode: mode, root: root)
        }
    }

    @Test
    func nominalKindsAreUsableFromJavaAndOfficialKotlin() throws {
        try withWorkspace { root in
            let result = try compile("""
            package api
            object Globals { var count = 40; fun next(): Int { count++; return count } }
            class Factory private constructor(val value: Int) {
                companion object Named { fun create(value: Int): Factory = Factory(value) }
            }
            data class Record(val value: Int, var name: String)
            data class Generic<T>(val value: T)
            enum class Mode(val code: Int) { FIRST(20), SECOND(22) }
            sealed class Shape {
                data class Value(val value: Int): Shape()
                object Empty: Shape()
            }
            """, root: root, mode: .jvmJar)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            let jar = root.appendingPathComponent("hello.jar").path
            try """
            import api.*;
            public class JavaConsumer {
                public static void main(String[] args) {
                    System.out.println(Globals.INSTANCE.next());
                    System.out.println(Factory.Named.create(42).getValue());
                    api.Record record = new api.Record(21, "left");
                    System.out.println(record.copy(42, "right"));
                    System.out.println(record.component1());
                    System.out.println(new Generic<String>("generic").copy("copied").getValue());
                    System.out.println(Mode.valueOf("SECOND").getCode());
                    System.out.println(Mode.values().length);
                    System.out.println(Mode.getEntries().get(0).name());
                    System.out.println(new Shape.Value(42).getValue());
                    System.out.println(Shape.Empty.INSTANCE == Shape.Empty.INSTANCE);
                }
            }
            """.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", jar, "JavaConsumer.java"], root: root)
            #expect(try java(["-cp", root.path + ":" + jar, "JavaConsumer"]).stdout == "41\n42\nRecord(value=42, name=right)\n21\ncopied\n22\n2\nFIRST\n42\ntrue\n")
            try """
            package consumer
            import api.*
            fun size(shape: Shape): Int = when (shape) {
                is Shape.Value -> shape.value
                Shape.Empty -> 0
            }
            fun main() {
                println(Globals.next())
                println(Factory.create(42).value)
                val record = Record(21, "left")
                println(record.copy(name = "right"))
                val (value, name) = record
                println(value); println(name)
                println(Generic("generic").copy().value)
                println(Mode.valueOf("SECOND").code)
                println(Mode.values().size)
                println(Mode.entries[0].name)
                println(size(Shape.Value(42)))
                println(size(Shape.Empty))
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["Consumer.kt", "-cp", jar, "-include-runtime", "-d", "consumer.jar"], root: root)
            let consumer = root.appendingPathComponent("consumer.jar").path
            for classpath in [consumer + ":" + jar, jar + ":" + consumer] {
                #expect(try java(["-cp", classpath, "consumer.ConsumerKt"]).stdout == "41\n42\nRecord(value=21, name=right)\n21\nleft\ngeneric\n22\n2\nFIRST\n42\n0\n")
            }
        }
    }

    @Test(arguments: [
        "package kotlin.jvm.internal\nclass DefaultConstructorMarker; sealed class Base; fun main() {}",
        "enum class E { A; constructor(value: Int): this() }; fun main() {}",
        "data class Bad(vararg val values: Int); fun main() {}",
        "sealed class Base; fun main() { Base() }",
        "enum class E { A }; fun main() { E() }",
        "object Singleton; fun main() { Singleton() }",
        "data class Point(val x: Int); fun main() { Point(1).copy(missing = 2) }",
        "sealed class Shape { object Empty: Shape(); class Full: Shape() }; fun value(s: Shape): Int = when(s) { Shape.Empty -> 0 }",
    ])
    func unsupportedOrInvalidM8ProgramsPreserveOutput(source: String) throws {
        try withWorkspace { root in
            let output = root.appendingPathComponent("hello.jar"), previous = Data("previous jar".utf8)
            try previous.write(to: output)
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 == 1, "\(source)")
            #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
            #expect(try Data(contentsOf: output) == previous)
        }
    }
}
#endif
