#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m15ReifiedOperationsAndForwarding(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            @JvmInline value class V(val value: Int)
            inline fun <reified T> test(value: Any?): Boolean = value is T
            inline fun <reified T> cast(value: Any?): T = value as T
            inline fun <reified T> safe(value: Any?): T? = value as? T
            inline fun <reified T: Any> klass(): kotlin.reflect.KClass<T> = T::class
            inline fun <reified T> array(n: Int): Array<T?> = arrayOfNulls<T>(n)
            inline fun <reified U> forward(value: Any?): Boolean = test<U>(value)
            inline fun <reified U> arrayTest(value: Any?): Boolean = test<Array<U>>(value)
            inline fun <reified T: Number> bounded(value: Any?): T = value as T
            fun main() {
                println(test<Int>(21)); println(test<String>(21)); println(test<Int?>(null)); println(test<Int>(null))
                println(cast<Int>(21)); println(safe<Int>("wrong")); println(safe<String>("text"))
                println(klass<Int>().simpleName); println(klass<Int>().java.name); println(klass<String>().java.name)
                val a = array<String>(2); a[1] = "item"; println(a.size); println(a[1]); println(a.javaClass.name)
                println(array<Int>(1).javaClass.name); println(forward<String>("yes"))
                println(arrayTest<String>(arrayOf("yes"))); println(arrayTest<String>(arrayOf(1)))
                println(test<V>(V(7))); println(cast<V>(V(8))); println(bounded<Int>(9))
                try { cast<String>(21) } catch (e: ClassCastException) { println("cast") }
            }
            """, expected: "true\nfalse\ntrue\nfalse\n21\nnull\ntext\nInt\njava.lang.Integer\njava.lang.String\n2\nitem\n[Ljava.lang.String;\n[Ljava.lang.Integer;\ntrue\ntrue\nfalse\ntrue\nV(value=8)\n9\ncast\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m15InlineSuspendResumesAndReifies(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            import kotlin.coroutines.*
            class Gate {
                var pending: Continuation<Int>? = null
                suspend fun await(): Int = suspendCoroutine { pending = it }
                fun release(n: Int) { pending!!.resume(n) }
            }
            class Sink: Continuation<Int> {
                override val context: CoroutineContext get() = EmptyCoroutineContext
                override fun resumeWith(result: Result<Int>) { println(result.getOrThrow()) }
            }
            inline suspend fun guarded(block: () -> Int): Int { try { return block() } finally { println("guard") } }
            inline suspend fun <reified T> check(value: Any?, block: () -> Int): Int {
                val result = block(); return if (value is T) result else 0
            }
            suspend fun early(): Int { guarded { return 7 }; return 0 }
            fun main() {
                val gate = Gate()
                val work: suspend () -> Int = { println(early()); check<String>("yes") { guarded { gate.await() } } }
                work.startCoroutine(Sink()); println("paused"); gate.release(42)
            }
            """, expected: "guard\n7\npaused\nguard\n42\n", mode: mode, root: root)
        }
    }

    @Test
    func m15OfficialKotlinConsumesReifiedAndInlineSuspend() throws {
        try withWorkspace { root in
            let result = try compile("""
            package api
            import kotlin.coroutines.*
            inline fun <reified T> test(v: Any?): Boolean = v is T
            inline fun <reified T> cast(v: Any?): T = v as T
            inline fun <reified T> safe(v: Any?): T? = v as? T
            inline fun <reified T: Any> klass(): kotlin.reflect.KClass<T> = T::class
            inline fun <reified T> array(n: Int): Array<T?> = arrayOfNulls<T>(n)
            inline fun <reified U> forward(v: Any?): Boolean = test<U>(v)
            inline fun <reified U> arrayTest(v: Any?): Boolean = test<Array<U>>(v)
            class Gate {
                var pending: Continuation<Int>? = null
                suspend fun await(): Int = suspendCoroutine { pending = it }
                fun release(n: Int) { pending!!.resume(n) }
            }
            inline fun <reified T> predicate(): (Any?) -> Boolean = { it is T }
            inline fun <reified T> factory(): (Int) -> Array<T?> = { arrayOfNulls<T>(it) }
            @JvmInline value class Text(val value: String)
            suspend fun text(): Text = Text("value")
            inline suspend fun inlineText(): Text = text()
            suspend fun maybeText(missing: Boolean = false): Text? = if (missing) null else Text("maybe")
            inline suspend fun inlineMaybe(missing: Boolean = false): Text? = maybeText(missing)
            suspend fun delayedTextValue(gate: Gate): Text = Text(if (gate.await() == 23) "23" else "wrong")
            inline suspend fun delayedText(gate: Gate): Text = delayedTextValue(gate)
            suspend fun delayedMaybeValue(gate: Gate): Text? = if (gate.await() == 0) null else Text("maybe")
            inline suspend fun delayedMaybe(gate: Gate): Text? = delayedMaybeValue(gate)
            inline suspend fun <reified T> typed(v: Any?, gate: Gate): Boolean { gate.await(); return v is T }
            suspend fun immediate(n: Int): Int = n
            inline suspend fun plus(n: Int = 20): Int = immediate(n) + 2
            inline suspend fun awaitPlus(gate: Gate, n: Int = 2): Int = gate.await() + n
            inline suspend fun guarded(block: () -> Int): Int { try { return block() } finally { println("guard") } }
            inline suspend fun <reified T> check(v: Any?, block: () -> Int): Int {
                val n = block(); return if (v is T) n else 0
            }
            """, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let jar = root.appendingPathComponent("hello.jar").path, runtime = try m11Runtime()
            try """
            package consumer
            import api.*
            import kotlin.coroutines.*
            suspend fun early(): Int { guarded { return 7 }; return 0 }
            fun main() {
                println(test<Int>(1)); println(test<String>(1)); println(test<Int?>(null)); println(test<Int>(null))
                println(cast<String>("cast")); println(safe<String>(1)); println(klass<Int>().java.name)
                println(array<String>(2).javaClass.name); println(array<Int>(1).javaClass.name)
                println(forward<String>("yes")); println(arrayTest<String>(arrayOf("yes")))
                println(predicate<Int>()(1)); println(predicate<String?>()(null)); println(factory<String>()(1).javaClass.name)
                val gate = Gate()
                val work: suspend () -> Int = { println(inlineText().value); println(inlineMaybe()?.value); println(inlineMaybe(true)); println(plus()); println(early()); check<String>("yes") { guarded { gate.await() } } }
                work.startCoroutine(object: Continuation<Int> {
                    override val context: CoroutineContext = EmptyCoroutineContext
                    override fun resumeWith(result: Result<Int>) { println(result.getOrThrow()) }
                })
                println("paused"); gate.release(42)
                val more: suspend () -> String = {
                    val v = delayedText(gate); val yes = typed<String>("yes", gate)
                    println(delayedMaybe(gate)?.value); println(delayedMaybe(gate))
                    if (yes) v.value else "wrong"
                }
                more.startCoroutine(object: Continuation<String> {
                    override val context: CoroutineContext = EmptyCoroutineContext
                    override fun resumeWith(result: Result<String>) { println(result.getOrThrow()) }
                })
                gate.release(23); gate.release(1); gate.release(2); gate.release(0)
            }
            """.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-cp", jar + ":" + runtime, "-d", "consumer.jar"], root: root)
            for cp in [jar + ":" + runtime, runtime + ":" + jar] {
                #expect(try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + cp, "consumer.ConsumerKt"]).stdout == "true\nfalse\ntrue\nfalse\ncast\nnull\njava.lang.Integer\n[Ljava.lang.String;\n[Ljava.lang.Integer;\ntrue\ntrue\ntrue\ntrue\n[Ljava.lang.String;\nvalue\nmaybe\nnull\n22\nguard\n7\npaused\nguard\n42\nmaybe\nnull\n23\n")
            }
            try """
            import api.*;
            import kotlin.coroutines.*;
            public class JavaConsumer {
                public static void main(String[] args) {
                    Continuation<Integer> sink = new Continuation<Integer>() {
                        public CoroutineContext getContext() { return EmptyCoroutineContext.INSTANCE; }
                        public void resumeWith(Object result) { kotlin.ResultKt.throwOnFailure(result); System.out.println(result); }
                    };
                    System.out.println(HelloKt.plus(5, sink));
                    Gate gate = new Gate();
                    Object result = HelloKt.awaitPlus(gate, 2, sink);
                    System.out.println(result == kotlin.coroutines.intrinsics.IntrinsicsKt.getCOROUTINE_SUSPENDED());
                    gate.release(40);
                }
            }
            """.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", jar + ":" + runtime, "JavaConsumer.java"], root: root)
            #expect(try java(["-cp", root.path + ":" + jar + ":" + runtime, "JavaConsumer"]).stdout == "7\ntrue\n42\n")
            let bytecode = try jvmTool("javap", ["-p", "-c", "-cp", jar, "api.HelloKt"], root: root).stdout
            #expect(bytecode.contains("$$forInline")); #expect(bytecode.contains("reifiedOperationMarker")); #expect(bytecode.contains("InlineMarker.mark"))
        }
    }
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m15EscapingReifiedClosures(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            inline fun <reified T> predicate(): (Any?) -> Boolean = { it is T }
            inline fun <reified T> caster(): (Any?) -> T? = { it as? T }
            inline fun <reified T: Any> token(): () -> String = { T::class.java.name }
            inline fun <reified T> factory(): (Int) -> Array<T?> = { arrayOfNulls<T>(it) }
            inline fun <reified T> unsafe(): (Any?) -> T = { it as T }
            inline fun <reified T: Number> bounded(n: Int): Array<T?> = arrayOfNulls<T>(n)
            inline fun <reified T> nested(): () -> ((Any?) -> Boolean) = { predicate<T>() }
            inline fun <reified T> arrays(): (Any?) -> Boolean = predicate<Array<T>>()
            fun main() {
                val p = predicate<Int>(); println(p(1)); println(p("wrong")); println(p(null))
                val nullable = predicate<String?>(); println(nullable(null)); println(nullable("yes")); println(nullable(1))
                val c = caster<Int>(); println(c(7)); println(c("wrong"))
                println(token<Int>()()); println(factory<String>()(2).javaClass.name)
                try { unsafe<String>()(null) } catch (e: NullPointerException) { println("null cast") }
                try { unsafe<String>()(1) } catch (e: ClassCastException) { println("bad cast") }
                println(bounded<Int>(1).javaClass.name)
                println(nested<String>()()("yes")); println(arrays<Int>()(arrayOf(1))); println(arrays<Int>()(arrayOf("wrong")))
            }
            """, expected: "true\nfalse\nfalse\ntrue\ntrue\nfalse\n7\nnull\njava.lang.Integer\n[Ljava.lang.String;\nnull cast\nbad cast\n[Ljava.lang.Integer;\ntrue\ntrue\nfalse\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [
        "fun <reified T> f(v: Any): Boolean = v is T; fun main() {}",
        "fun <T> f(v: Any): Boolean = v is T; fun main() {}",
        "inline fun <reified T> f(): String = T::class.java.name; fun <U> g(): String = f<U>(); fun main() {}"
    ])
    func m15InvalidReifiedProgramsPreserveOutput(source: String) throws {
        try withWorkspace { root in
            let output = root.appendingPathComponent("hello.jar"), sentinel = Data("previous jar".utf8)
            try sentinel.write(to: output)
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 == 1)
            #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
            #expect(try Data(contentsOf: output) == sentinel)
        }
    }

}
#endif
