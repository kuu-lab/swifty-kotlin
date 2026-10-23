#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m9NamedAndDefaultArgumentsPreserveEvaluationOrder(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            fun mark(n: Int): Int { println(n); return n }
            fun combine(a: Int = mark(1), b: Int = a + mark(2), c: Int = mark(3)): Int = a * 100 + b * 10 + c
            fun Int.decorate(left: Int = this, right: Int = 2): Int = this + left + right
            class Box(val a: Int = mark(4), val b: Int = a + mark(5)) {
                constructor(text: String, n: Int = 5): this(b = n, a = 0)
                fun result(offset: Int = a): Int = a + b + offset
            }
            fun main() {
                println(combine(c = mark(9), a = mark(7)))
                println(combine())
                println(2.decorate(right = 4))
                println(Box(b = mark(6)).result())
                println(Box("hello").result(offset = 2))
                println(Box().result())
            }
            """, expected: "9\n7\n2\n799\n1\n2\n3\n133\n8\n6\n4\n14\n7\n4\n5\n17\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m9InheritedInterfaceAndInlineDefaults(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            interface Value { fun value(n: Int = 21): Int }
            open class Base { open fun value(n: Int = 20): Int = n }
            class Derived: Base() { override fun value(n: Int): Int = n * 2 }
            class Direct: Value { override fun value(n: Int): Int = n + 1 }
            inline fun calculate(n: Int = 21, block: (Int) -> Int = { it * 2 }): Int = block(n)
            inline fun choose(n: Int = 1, block: () -> Int): Int = block() + n
            fun early(): Int { choose(block = { return 42 }); return 0 }
            fun main() {
                val direct = Direct()
                val value: Value = direct
                println(direct.value())
                println(value.value())
                println(Derived().value())
                println(calculate())
                println(calculate(block = { it + 1 }))
                println(calculate(block = { it * 2 }, n = 10))
                println(early())
            }
            """, expected: "22\n22\n40\n42\n22\n20\n42\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m9InnerInstancesAndNestedOuterChains(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            class Outer(private var value: Int) {
                private fun read(): Int = value
                inner class Inner(val extra: Int = value) {
                    fun sum(): Int = read() + extra
                    fun change(n: Int) { value = n }
                    fun owner(): Outer = this@Outer
                    inner class Deep { fun sum(): Int = this@Inner.sum() + this@Outer.read() }
                }
                fun make(): Inner = Inner()
            }
            class Names(val p0: Int) { inner class Inner(val p1: Int = p0, val p2: Int = p1 + 1) }
            fun main() {
                println(Names(40).Inner().p2)
                val first = Outer(10)
                val second = Outer(20)
                val a = first.Inner(extra = 2)
                val b = second.make()
                println(a.sum()); println(b.sum())
                a.change(30)
                println(a.sum()); println(b.sum())
                println(a.owner() == first)
                println(a.Deep().sum())
            }
            """, expected: "41\n12\n40\n32\n40\ntrue\n62\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m9AnonymousObjectsCaptureAndInitializePerInstance(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            interface Counter { fun next(): Int }
            open class Base(val seed: Int = 10) { open fun next(): Int = seed }
            fun counter(start: Int): Counter {
                var n = start
                val first = object: Counter { override fun next(): Int { n++; return n } }
                val second = object: Counter { override fun next(): Int { n += 10; return n } }
                first.next()
                second.next()
                return first
            }
            class Owner(private var n: Int) {
                private fun read(): Int = n
                fun make(): Counter = object: Counter {
                    override fun next(): Int { n++; return read() }
                }
            }
            fun main() {
                val a = counter(0); val b = counter(100)
                println(a.next()); println(b.next()); println(a.next())
                var local = 2
                val x = object: Base(seed = local + 1), Counter {
                    val initial = local
                    init { local += 10 }
                    override fun next(): Int = super.next() + local + initial
                    fun own(): Int = initial
                }
                println(x.next()); println(x.own()); println(local)
                val owner = Owner(20)
                val c = owner.make(); val d = owner.make()
                println(c.next()); println(d.next())
                val anonymous = object { val answer = 42; fun read(): Int = answer }
                println(anonymous.read())
            }
            """, expected: "12\n112\n13\n17\n2\n12\n21\n22\n42\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m9DataObjectsAndDataConstructorDefaults(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            package demo
            open class Named { final override fun toString(): String = "inherited" }
            data object Child: Named()
            sealed interface Result
            data object Empty: Result
            class Container { data object Nested }
            data object Custom { override fun toString(): String = "custom" }
            data class Point(val x: Int = 21, val label: String = "answer")
            fun main() {
                println(Empty); println(Container.Nested); println(Custom); println(Child)
                println(Empty == Empty)
                println(Empty.hashCode())
                println(Container.Nested.hashCode())
                println(Point()); println(Point(label = "named").copy(x = 42))
            }
            """, expected: "Empty\nNested\ncustom\ninherited\ntrue\n1759660386\n2065108975\nPoint(x=21, label=answer)\nPoint(x=42, label=named)\n", mode: mode, root: root, mainClass: "demo.HelloKt")
        }
    }
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m9CapturesExistDuringBaseInitializationAndAnonymousDefaults(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            open class Base { init { println(value()) }; open fun value(): Int = 0 }
            class Outer(private val x: Int) {
                open inner class Parent: Base() { override fun value(): Int = x }
                inner class Child: Parent()
                fun anonymous(): Base = object: Parent() { override fun value(): Int = x + 1 }
            }
            fun main() {
                val x = 42
                val a = object: Base() { override fun value(): Int = x }
                val b = object { fun result(n: Int = x): Int = n }
                println(b.result())
                val outer = Outer(20)
                outer.Child()
                outer.anonymous()
            }
            """, expected: "42\n42\n20\n21\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m9ObjectEnumSuperDefaultsAndExplicitNoarg(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            open class Base(val a: Int = 20, val b: Int = 22)
            object Child: Base(b = 42)
            enum class Entry(val value: Int = 42) { FIRST, SECOND(value = 21) { override fun read(): Int = value * 2 }; open fun read(): Int = value }
            class Box(val value: Int = 1) { constructor(): this(42) }
            fun main() { println(Child.a); println(Child.b); println(Entry.FIRST.read()); println(Entry.SECOND.read()); println(Box().value) }
            """, expected: "20\n42\n42\n42\n42\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m9MultipleMasksWideValuesAndThrowingDefaults(mode: EmitMode) throws {
        try withWorkspace { root in
            let params = (0..<34).map { "p\($0): Int = \($0 + 1)" }.joined(separator: ", ")
            try runM4("""
            fun many(\(params)): Int = p0 + p31 + p32 + p33
            class Wide(val first: Long = 40L, val second: Double = 2.0, val text: String = "wide")
            fun fail(): Int { throw IllegalStateException("default") }
            fun optional(n: Int = fail()): Int = n
            fun nullable(text: String? = null): String? = text
            fun direct(n: Int = throw IllegalStateException("direct")): Int = n
            inline fun stop(n: Int = throw IllegalStateException("stop")): Int = n
            fun main() {
                println(many()); println(many(p33 = 1, p0 = 2)); println(many(p31 = 3, p32 = 4))
                val wide = Wide(second = 3.5)
                println(wide.first); println(wide.second); println(wide.text)
                println(optional(n = 42))
                try { println(optional()) } catch (error: IllegalStateException) { println("caught") }
                println(nullable()); println(nullable(text = "provided"))
                try { direct() } catch (error: IllegalStateException) { println("direct") }
                try { stop() } catch (error: IllegalStateException) { println("stop") }
                println(direct(n = 42))
            }
            """, expected: "100\n68\n42\n40\n3.5\nwide\n42\ncaught\nnull\nprovided\ndirect\nstop\n42\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m9GenericAnonymousAndInnerClasses(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            interface Getter<T> { fun get(): T }
            fun <T> getter(value: T): Getter<T> = object: Getter<T> { override fun get(): T = value }
            class Outer<T>(val value: T) { inner class Inner<U>(val other: U) { fun first(): T = value; fun second(): U = other } }
            fun main() { val x = Outer(42).Inner("inner"); println(x.first()); println(x.second()); println(getter("anonymous").get()) }
            """, expected: "42\ninner\nanonymous\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m9SuspendDefaultCallsUseContinuationBeforeMasks(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM7Coroutine("""
            import kotlin.coroutines.*
            interface Value { suspend fun result(n: Int = 21): Int }
            class Impl: Value { override suspend fun result(n: Int): Int = n * 2 }
            suspend fun suspended(a: Int = 20, b: Int = a + 2): Int = suspendCoroutine<Int> { it.resume(a + b) }
            suspend fun Int.add(n: Int = 2): Int = suspended(a = this, b = n)
            suspend fun main() {
                println(suspended()); println(suspended(b = 22)); println(40.add())
                val v: Value = Impl(); println(v.result())
            }
            """, expected: "42\n42\n42\n42\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [
        "fun value(a: Int = 1): Int = a; fun main() { value(missing = 2) }",
        "fun value(a: Int = 1): Int = a; fun main() { value(a = 1, a = 2) }",
        "class Outer { inner class Inner }; fun main() { Outer.Inner() }",
        "data object Bad { override fun hashCode(): Int = 1 }; fun main() {}",
        "fun make() = object { val value = 42 }; fun main() { println(make().value) }",
        "interface A; interface B; fun make() = object: A, B {}; fun main() {}",
    ])
    func m9InvalidArgumentsAndNominalsPreserveOutput(source: String) throws {
        try withWorkspace { root in
            let output = root.appendingPathComponent("hello.jar"), previous = Data("previous jar".utf8)
            try previous.write(to: output)
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 == 1)
            #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
            #expect(try Data(contentsOf: output) == previous)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m9NamedArrayAndHigherOrderArguments(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun mark(n: Int): Int { println(n); return n }
            fun initializer(): (Int) -> Int { println("init"); return { it + 1 } }
            fun operation(): (Int, Int) -> Int { println("operation"); return { a, b -> a + b } }
            fun main() {
                val values = IntArray(init = initializer(), size = mark(3))
                println(message = values.fold(operation = operation(), initial = mark(10)))
                println(values.map(transform = { it * 2 })[2])
            }
            """, expected: "init\n3\noperation\n10\n16\n6\n", mode: mode, root: root)
        }
    }

    @Test
    func m9HiddenConstructorSlotsAreIncludedInLimits() throws {
        try withWorkspace { root in
            let parameters = (0..<254).map { "p\($0): Int" }.joined(separator: ", ")
            let result = try compile("class Outer { inner class Inner(\(parameters)) }; fun main() {}", root: root, mode: .jvmJar)
            #expect(result.0 == 1)
            #expect(result.1.contains { $0.message.contains("slot limit") })
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.jar").path))
        }
    }

    @Test
    func m9JarDefaultArgumentsInnerAndDataObjectABI() throws {
        try withWorkspace { root in
            let source = """
            package api
            interface Getter<T> { fun get(): T }
            fun <T> getter(value: T) = object: Getter<T> { override fun get(): T = value }
            fun anonymous() = object { val value = 42 }
            fun supplier() = { object: Getter<Int> { override fun get(): Int = 42 } }
            class Holder { val value = object: Getter<Int> { override fun get(): Int = 42 } }
            data object Done
            class Outer(val n: Int = 20) {
                inner class Inner(val value: Int = n) { fun sum(delta: Int = 2): Int = n + value + delta }
            }
            interface Value { fun value(n: Int = 21): Int }
            class Impl: Value { override fun value(n: Int): Int = n * 2 }
            fun sum(a: Int = 20, b: Int = 22): Int = a + b
            fun Int.add(n: Int = 2): Int = this + n
            inline fun calculate(n: Int = 21, block: (Int) -> Int = { it * 2 }): Int = block(n)
            inline fun guarded(n: Int = 1, block: () -> Int): Int {
                try { return block() + n } finally { println("finally") }
            }
            suspend fun suspended(n: Int = 42): Int = n
            """
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            try """
            import api.*
            fun early(): Int { calculate(block = { return 42 }); return 0 }
            fun finalEarly(): Int { guarded(block = { return 42 }); return 0 }
            suspend fun main() {
                println(early())
                println(finalEarly())
                println(sum(b = 22))
                println(getter(supplier()().get()).get())
                println(40.add())
                val outer = Outer()
                println(outer.Inner().sum())
                println(outer.Inner(value = 10).sum(delta = 12))
                val v: Value = Impl()
                println(v.value())
                println(calculate())
                println(calculate(block = { it + 1 }))
                println(suspended())
                println(Done)
            }
            """.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-classpath", "hello.jar", "-include-runtime", "-d", "consumer.jar"], root: root)
            for order in ["hello.jar:consumer.jar", "consumer.jar:hello.jar"] {
                let cp = order.split(separator: ":").map { root.appendingPathComponent(String($0)).path }.joined(separator: ":")
                let run = try java(["-cp", cp, "ConsumerKt"])
                #expect(run.stdout == "42\nfinally\n42\n42\n42\n42\n42\n42\n42\n42\n22\n42\nDone\n")
            }
            try """
            import api.*;
            public class Consumer {
                public static void main(String[] args) throws Exception {
                    Object anonymous = api.HelloKt.anonymous();
                    Outer outer = new Outer();
                    System.out.println(outer.new Inner(20).sum(2));
                    System.out.println(api.HelloKt.sum(20, 22));
                    var ctor = Done.class.getDeclaredConstructor();
                    ctor.setAccessible(true);
                    Object twin = ctor.newInstance();
                    System.out.println(twin.equals(Done.INSTANCE));
                    System.out.println(twin.hashCode() == Done.INSTANCE.hashCode());
                    System.out.println(!java.lang.reflect.Modifier.isStatic(Outer.Inner.class.getModifiers()));
                    System.out.println(Outer.Inner.class.getEnclosingClass() == Outer.class);
                }
            }
            """.write(to: root.appendingPathComponent("Consumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", "hello.jar", "Consumer.java"], root: root)
            let run = try java(["-cp", root.path + ":" + root.appendingPathComponent("hello.jar").path, "Consumer"])
            #expect(run.stdout == "42\n42\ntrue\ntrue\ntrue\ntrue\n")
        }
    }

}
#endif
