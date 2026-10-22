#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m16ReifiedReferencesSpecializeAndEscape(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            @JvmInline value class V(val value: Int)
            inline fun <reified T> cast(v: Any?): T = v as T
            inline fun <reified T> safe(v: Any?): T? = v as? T
            inline fun <reified T> identity(v: T): T = v
            inline fun <reified T> defaulted(v: T, n: Int = 2): T = v
            inline fun <reified T> forward(): (Any?) -> T = ::cast
            inline fun <reified T> T.token(): String = T::class.java.name
            class Holder(val n: Int) { inline fun <reified T> same(v: T): T = v }
            var evaluations = 0
            fun owner(): Holder { evaluations++; return Holder(evaluations) }
            fun main() {
                val text: (Any?) -> String = ::cast; println(text("yes"))
                val number: (Int) -> Int = ::identity; println(number(21))
                val nullable: (Any?) -> String? = ::cast; println(nullable(null))
                val safe: (Any?) -> Int? = ::safe; println(safe("wrong")); println(safe(42))
                val v: (Any?) -> V = ::cast; println(v(V(8)).value)
                val a: (Any?) -> Array<String> = ::cast; println(a(arrayOf("item"))[0])
                val member: (String) -> String = owner()::same; println(member("bound")); println(evaluations)
                val unbound: (Holder, Int) -> Int = Holder::same; println(unbound(Holder(1), 7))
                val ext: (String) -> String = String::token; println(ext("value"))
                val bound: () -> String = "value"::token; println(bound())
                val default: (String) -> String = ::defaulted; println(default("default")); println(default is kotlin.reflect.KFunction<*>)
                val unit: () -> Unit = "value"::token; unit(); println(unit is kotlin.reflect.KFunction<*>)
                println(forward<String>()("escaped")); println(forward<Int?>()(null))
                try { text(null) } catch (e: NullPointerException) { println("null") }
                try { text(1) } catch (e: ClassCastException) { println("cast") }
                println((text as kotlin.reflect.KFunction<*>).name); println((text as kotlin.reflect.KFunction<*>).isInline)
            }
            """, expected: "yes\n21\nnull\nnull\n42\n8\nitem\nbound\n1\n7\njava.lang.String\njava.lang.String\ndefault\nfalse\nfalse\nescaped\nnull\nnull\ncast\ncast\ntrue\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m16AnonymousObjectsCaptureRuntimeTypes(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            interface Probe {
                val initial: Boolean
                val name: String
                fun matches(v: Any?): Boolean
                fun cast(v: Any?): Any?
                fun safe(v: Any?): Any?
                fun array(n: Int): Array<out Any?>
                fun nested(): (Any?) -> Boolean
            }
            inline fun <reified T> probe(seed: Any?): Probe = object: Probe {
                override val initial = seed is T
                override val name: String get() = T::class.java.name
                override fun matches(v: Any?): Boolean = v is T
                override fun cast(v: Any?): Any? = v as T
                override fun safe(v: Any?): Any? = v as? T
                override fun array(n: Int): Array<out Any?> = arrayOfNulls<T>(n)
                override fun nested(): (Any?) -> Boolean = { it is T }
            }
            interface Box<T> { fun get(): T; fun matches(v: Any?): Boolean }
            inline fun <reified T> box(value: T): Box<T> = object: Box<T> {
                override fun get(): T = value
                override fun matches(v: Any?): Boolean = v is T
            }
            fun main() {
                val a = probe<Int>(1); val b = probe<String?>(null)
                println(a.javaClass == probe<Int>(2).javaClass)
                println(a.initial); println(b.initial); println(a.name); println(b.name)
                println(a.matches(2)); println(a.matches("wrong")); println(a.matches(null)); println(b.matches(null))
                println(a.cast(7)); println(a.safe("wrong")); println(b.cast(null))
                println(a.array(2).javaClass.name); println(b.array(1).javaClass.name)
                println(a.nested()(1)); println(b.nested()(null))
                try { a.cast(null) } catch (e: NullPointerException) { println("null") }
                try { a.cast("wrong") } catch (e: ClassCastException) { println("cast") }
                val x = box(9); val y = box("text"); println(x.get()); println(y.get()); println(x.matches("wrong")); println(y.matches("yes"))
            }
            """, expected: "false\ntrue\ntrue\njava.lang.Integer\njava.lang.String\ntrue\nfalse\nfalse\ntrue\n7\nnull\nnull\n[Ljava.lang.Integer;\n[Ljava.lang.String;\ntrue\ntrue\nnull\ncast\n9\ntext\nfalse\ntrue\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m16SuspendReferencesAndObjectsResumeWithTypeCaptures(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            import kotlin.coroutines.*
            class Gate {
                var pending: Continuation<Int>? = null
                suspend fun await(): Int = suspendCoroutine { pending = it }
                fun release(n: Int) { pending!!.resume(n) }
            }
            inline suspend fun <reified T> checked(v: T, gate: Gate): Boolean { gate.await(); return v is T }
            inline fun <reified U> reference(): suspend (U, Gate) -> Boolean = ::checked
            interface Probe { suspend fun test(v: Any?, gate: Gate): Boolean }
            inline fun <reified T> probe(): Probe = object: Probe {
                override suspend fun test(v: Any?, gate: Gate): Boolean { gate.await(); return v is T }
            }
            fun main() {
                val gate = Gate()
                val work: suspend () -> Boolean = {
                    val f: suspend (String, Gate) -> Boolean = ::checked
                    println(f("yes", gate)); println(reference<String?>()(null, gate))
                    probe<Int>().test(1, gate)
                }
                work.startCoroutine(object: Continuation<Boolean> {
                    override val context: CoroutineContext = EmptyCoroutineContext
                    override fun resumeWith(result: Result<Boolean>) { println(result.getOrThrow()) }
                })
                println("paused"); gate.release(1); gate.release(2); gate.release(3)
            }
            """, expected: "paused\ntrue\ntrue\ntrue\n", mode: mode, root: root)
        }
    }
    @Test
    func m16OfficialKotlinConsumesReferencesAndAnonymousCaptures() throws {
        try withWorkspace { root in
            let compiled = try compile("""
            package api
            import kotlin.coroutines.*
            inline fun <reified T> cast(v: Any?): T = v as T
            inline fun <reified U> reference(): (Any?) -> U = ::cast
            inline fun <reified T> identity(v: T): T = v
            inline fun <reified T> defaultName(sample: T, klass: kotlin.reflect.KClass<*> = T::class): String? = klass.simpleName
            inline fun <reified U> defaultFactory(): (U) -> String? = ::defaultName
            interface Plain { fun value(): Int }
            inline fun <reified T> plain(): Plain = object: Plain { override fun value(): Int = 42 }
            fun javaReference(): (Any?) -> String = reference<String>()
            fun javaProbe(): Probe<Int> = probe<Int>()
            interface Probe<T> {
                val name: String
                fun matches(v: Any?): Boolean
                fun array(n: Int): Array<T?>
                fun reference(): (Any?) -> T
                fun nested(): (Any?) -> Boolean
            }
            open class Base(val klass: Class<*>)
            inline fun <reified T> probe(): Probe<T> = object: Base(T::class.java), Probe<T> {
                override val name = klass.name
                override fun matches(v: Any?): Boolean = v is T
                override fun array(n: Int): Array<T?> = arrayOfNulls<T>(n)
                override fun reference(): (Any?) -> T = ::cast
                override fun nested(): (Any?) -> Boolean = { it is T }
            }
            class Gate {
                var pending: Continuation<Int>? = null
                suspend fun await(): Int = suspendCoroutine { pending = it }
                fun release(n: Int) { pending!!.resume(n) }
            }
            inline suspend fun <reified T> checked(v: T, gate: Gate): T { gate.await(); return v as T }
            inline fun <reified T> suspended(): suspend (T, Gate) -> T = ::checked
            interface Async { suspend fun matches(v: Any?, gate: Gate): Boolean }
            inline fun <reified T> async(): Async = object: Async {
                override suspend fun matches(v: Any?, gate: Gate): Boolean { gate.await(); return v is T }
            }
            """, root: root, mode: .jvmJar)
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")
            let jar = root.appendingPathComponent("hello.jar").path, runtime = try m11Runtime()
            try """
            package consumer
            import api.*
            import kotlin.coroutines.*
            import kotlin.reflect.*
            fun main() {
                val a = reference<String>(); val b = reference<Int?>()
                println(a("yes")); println(b(null))
                val r = a as KFunction<*>
                println(r.name); println(r.isInline); println(r.typeParameters.single().isReified)
                try { r.call("yes") } catch (e: java.lang.reflect.InvocationTargetException) { println(e.cause is UnsupportedOperationException) }
                val id: (String) -> String = ::identity
                println((id as KFunction<*>).call("reflect"))
                println(defaultFactory<String>()("x")); println(plain<Int>().value()); println(plain<Int>().javaClass == plain<Int>().javaClass)
                val p = probe<Int>(); val q = probe<String?>()
                println(p.name); println(q.name); println(p.matches(1)); println(q.matches(null))
                println(p.array(2).javaClass.name); println(q.array(2).javaClass.name)
                println(p.reference()(8)); println(q.reference()(null)); println(q.nested()(null))
                println(p.javaClass == probe<Int>().javaClass)
                val gate = Gate()
                val work: suspend () -> String = {
                    val f = suspended<String>(); println(f("resumed", gate))
                    println(async<String?>().matches(null, gate)); "done"
                }
                work.startCoroutine(object: Continuation<String> {
                    override val context: CoroutineContext = EmptyCoroutineContext
                    override fun resumeWith(result: Result<String>) { println(result.getOrThrow()) }
                })
                println("paused"); gate.release(1); gate.release(2)
            }
            """.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-cp", jar + ":" + runtime, "-d", "consumer.jar"], root: root)
            for cp in [jar + ":" + runtime, runtime + ":" + jar] {
                #expect(try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + cp, "consumer.ConsumerKt"]).stdout == "yes\nnull\ncast\ntrue\ntrue\ntrue\nreflect\nString\n42\nfalse\njava.lang.Integer\njava.lang.String\ntrue\ntrue\n[Ljava.lang.Integer;\n[Ljava.lang.String;\n8\nnull\ntrue\nfalse\npaused\nresumed\ntrue\ndone\n")
            }
            try """
            import api.*;
            public class JavaConsumer {
                public static void main(String[] args) {
                    System.out.println(HelloKt.javaReference().invoke("java"));
                    System.out.println(HelloKt.javaProbe().matches(1));
                    System.out.println(HelloKt.javaProbe().getName());
                }
            }
            """.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", jar + ":" + runtime, "JavaConsumer.java"], root: root)
            #expect(try java(["-cp", root.path + ":" + jar + ":" + runtime, "JavaConsumer"]).stdout == "java\ntrue\njava.lang.Integer\n")
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m16GenericCaptureLayoutAndNestedObjects(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                val a = box(1); val b = box("text"); println(a.get()); println(b.get())
                val x = mutableBox(2); val y = mutableBox("before")
                x.set(7); y.set("after"); println(x.get()); println(y.get()); println(x.matches(7)); println(y.matches(null))
                val p = nested<Int, String?>(); println(p.first(1)); println(p.second(null)); println(p.first("wrong"))
                val inner = Outer(4).Inner()
                val f: (Int) -> Int = inner::add; println(f(3))
                println(memberReference<Int, String>()("wrong")); println(memberReference<String, String>()("yes")); println(memberReference<String?, String?>()(null))
                val e = 5.self(); val g = "word".self(); println(e.get()); println(g.get())
            }
            interface Box<T> { fun get(): T }
            inline fun <reified T> box(value: T): Box<T> = object: Box<T> { override fun get(): T = value }
            interface Mutable<T> { fun get(): T; fun set(value: T); fun matches(v: Any?): Boolean }
            inline fun <reified T> mutableBox(value: T): Mutable<T> {
                var current = value
                return object: Mutable<T> {
                    override fun get(): T = current
                    override fun set(value: T) { current = value }
                    override fun matches(v: Any?): Boolean = v is T
                }
            }
            interface Dual { fun first(v: Any?): Boolean; fun second(v: Any?): Boolean }
            inline fun <reified A, reified B> nested(): Dual {
                val outer = object: Dual {
                    override fun first(v: Any?): Boolean = v is A
                    override fun second(v: Any?): Boolean {
                        val inner = object { fun test(): Boolean = v is B }
                        return inner.test()
                    }
                }
                return outer
            }
            inline fun <reified A, reified B> memberReference(): (B) -> Boolean {
                val target = object { inline fun <reified C> matches(v: C): Boolean = v is A }
                return target::matches
            }
            inline fun <reified T> T.self(): Box<Any?> = object: Box<Any?> { override fun get(): Any? = this@self }
            class Outer(val value: Int) {
                inner class Inner { inline fun <reified T> add(n: T): Int = if (n is Int) value + n else 0 }
            }
            """, expected: "1\ntext\n7\nafter\ntrue\nfalse\ntrue\ntrue\nfalse\n7\nfalse\ntrue\ntrue\n5\nword\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m16AdaptedReferencesAndSuspendValueResults(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            import kotlin.coroutines.*
            @JvmInline value class Text(val value: String)
            inline fun <reified T> identity(v: T): T = v
            inline suspend fun <reified T> suspended(v: T): T = v
            fun main() {
                val f: suspend (Int) -> Int = ::identity
                println(f is kotlin.reflect.KFunction<*>)
                val g: suspend (Text) -> Text = ::suspended
                val work: suspend () -> Int = { println(g(Text("value")).value); f(42) }
                work.startCoroutine(object: Continuation<Int> {
                    override val context: CoroutineContext = EmptyCoroutineContext
                    override fun resumeWith(result: Result<Int>) { println(result.getOrThrow()) }
                })
            }
            """, expected: "false\nvalue\n42\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m16SAMDefaultTokensAndReferenceEquality(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun interface Action { fun run(value: String): String }
            inline fun <reified T> cast(v: Any?): T = v as T
            inline fun <reified T> identity(v: T): T = v
            inline fun <reified T> label(sample: T, klass: kotlin.reflect.KClass<*> = T::class): String? = klass.simpleName
            inline fun <reified U> factory(): (U) -> String? = ::label
            interface Names { val eager: String; fun ref(): (Any?) -> Any? }
            inline fun <reified T> names(): Names = object: Names {
                override val eager = T::class.java.name
                override fun ref(): (Any?) -> T = ::cast
            }
            fun main() {
                val action: Action = Action(::identity); println(action.run("sam"))
                println(factory<String>()("x")); println(factory<Int>()(1))
                val a: (String) -> String = ::identity; val b: (Int) -> Int = ::identity
                println(a == b)
                val n = names<Array<Int>>(); println(n.eager)
                println((n.ref()(arrayOf(1)) as Array<Int>)[0])
            }
            """, expected: "sam\nString\nInt\ntrue\n[Ljava.lang.Integer;\n1\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m16AnonymousLazyCapturesReifiedType(mode: EmitMode) throws {
        try withWorkspace { root in
            // Kotlin 2.4.20 leaves an unresolved marker in this nested lazy
            // lambda. Pin the candidate's runtime result independently.
            let compiled = try compile("""
            interface Names { val name: String }
            inline fun <reified T> names(): Names = object: Names {
                override val name by lazy { T::class.java.name }
            }
            fun main() {
                val a = names<Array<Int>>(); val b = names<String?>()
                println(a.name); println(a.name); println(b.name)
            }
            """, root: root, mode: mode)
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")
            let runtime = try m11Runtime(), artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            for cp in [artifact + ":" + runtime, runtime + ":" + artifact] {
                #expect(try java(["-cp", cp, "HelloKt"]).stdout == "[Ljava.lang.Integer;\n[Ljava.lang.Integer;\njava.lang.String\n")
            }
        }
    }

    @Test
    func m16ReferenceCaptureLimitIncludesConstructorReceiver() throws {
        try withWorkspace { root in
            let count = 127
            let typeNames = (0..<count).map { "T\($0)" }, outerNames = (0..<count).map { "U\($0)" }
            let parameters = typeNames.map { "reified " + $0 }.joined(separator: ", ")
            let outerParameters = outerNames.map { "reified " + $0 }.joined(separator: ", ")
            let body = typeNames.map { $0 + "::class" }.joined(separator: "; ")
            let source = """
            class Packed<\(typeNames.joined(separator: ", "))>
            class Owner {
                inline fun <\(parameters)> value(): Packed<\(typeNames.joined(separator: ", "))> { \(body); return Packed() }
            }
            inline fun <\(outerParameters)> reference(owner: Owner): () -> Packed<\(outerNames.joined(separator: ", "))> = owner::value
            """
            let output = root.appendingPathComponent("hello.jar"), sentinel = Data("previous jar".utf8)
            try sentinel.write(to: output)
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 == 1)
            #expect(result.1.contains { $0.code == "KSWIFTK-JVM-0001" && $0.message.contains("reference parameter slot limit") }, "\(result.1.map(\.message))")
            #expect(try Data(contentsOf: output) == sentinel)
        }
    }

}
#endif
