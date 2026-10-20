#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m14InlineValueClassesAndNonLocalReturns(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            @JvmInline value class V(val value: Int) {
                inline fun apply(other: V, block: (V) -> V): V = block(other)
            }
            @JvmInline value class Wide(val value: Long)
            @JvmInline value class Box<T>(val value: T)
            inline fun transform(v: V = V(21), block: (V) -> V = { it }): V = block(v)
            inline fun V.plus(other: V = V(1)): V = V(value + other.value)
            inline fun <T> identity(v: Box<T>): Box<T> = v
            inline fun wide(v: Wide, block: (Wide) -> Wide): Wide = block(v)
            inline fun guarded(v: V, block: (V) -> V): V {
                try { return block(v) } finally { println("finally") }
            }
            fun early(): V { guarded(V(7)) { return it }; return V(0) }
            fun main() {
                println(transform()); println(transform(V(20)) { it.plus(V(2)) })
                println(V(1).apply(V(42)) { it }); println(identity(Box("generic")))
                println(wide(Wide(20L)) { Wide(it.value + 2L) }); println(early())
            }
            """, expected: "V(value=21)\nV(value=22)\nV(value=42)\nBox(value=generic)\nWide(value=22)\nfinally\nV(value=7)\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m14SuspendValueClassesDefaultsAndDispatch(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            @JvmInline value class V(val value: Int)
            @JvmInline value class Wide(val value: Long)
            interface Source { suspend fun get(v: V): V }
            open class Base: Source { override suspend fun get(v: V): V = V(v.value + 1) }
            class Child: Base() { override suspend fun get(v: V): V { val x = super.get(v); return V(x.value + 1) } }
            suspend fun echo(v: V = V(21)): V = v
            suspend fun optional(v: V? = null): V? = v
            suspend fun V.plus(other: V = V(1)): V = V(value + other.value)
            suspend fun wide(v: Wide): Wide = v
            suspend fun number(v: Int): Int = v
            suspend fun main() {
                println(echo()); println(optional()); println(optional(V(7))); println(V(20).plus())
                val source: Source = Child(); println(source.get(V(40)))
                val callback: suspend () -> V = { echo(V(42)) }; println(callback())
                println(wide(Wide(9L)))
                val ref: suspend (V) -> V = ::echo; println(ref(V(9)))
                val plain: suspend (Int) -> Int = ::number; println(plain(10))
                println(V(number(11)))
            }
            """, expected: "V(value=21)\nnull\nV(value=7)\nV(value=21)\nV(value=42)\nV(value=42)\nWide(value=9)\nV(value=9)\n10\nV(value=11)\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m14ReferenceSuspendResultsAndDelayedResume(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            import kotlin.coroutines.*
            @JvmInline value class Text(val value: String)
            @JvmInline value class Maybe(val value: String?)
            @JvmInline value class ArrayValue(val value: IntArray)
            @JvmInline value class Box<T>(val value: T)
            class Gate {
                var pending: Continuation<Text>? = null
                suspend fun await(v: Text = Text("default")): Text = suspendCoroutine { pending = it }
                fun release(v: Text) { pending!!.resume(v) }
                fun reject() { pending!!.resumeWithException(IllegalStateException("failed")) }
            }
            class Sink: Continuation<Text> {
                override val context: CoroutineContext get() = EmptyCoroutineContext
                override fun resumeWith(result: Result<Text>) { println(result.getOrThrow()) }
            }
            suspend fun immediate(v: Text): Text = suspendCoroutine { it.resume(v) }
            suspend fun make(): Text = Text("made")
            suspend fun fromInt(n: Int = 1): Text = Text("number")
            suspend fun optional(v: Text? = null): Text? = v
            suspend fun maybe(v: Maybe = Maybe(null)): Maybe = v
            suspend fun array(v: ArrayValue = ArrayValue(intArrayOf(1, 2))): ArrayValue = v
            suspend fun boxed(v: Maybe?): Maybe? = v
            suspend fun <T> generic(v: Box<T>): Box<T> = v
            fun main() {
                val gate = Gate()
                val work: suspend () -> Text = {
                    var n = 20L
                    val first = immediate(Text("sync")); println(first)
                    val ref: suspend (Text) -> Text = ::immediate; println(ref(Text("reference")))
                    println(make()); println(fromInt())
                    println(optional()); println(optional(Text("some"))); println(maybe()); println(boxed(Maybe(null))); println(array())
                    println(generic(Box(42))); println(generic(Box<String?>(null)))
                    val deferred: suspend (Text) -> Text = gate::await
                    val value = deferred(Text("ignored")); n += 2L; println(n); println(value)
                    try { gate.await(Text("failure")) } catch (e: IllegalStateException) { println(e.message) }
                    finally { println("finally") }
                    Text("done")
                }
                work.startCoroutine(Sink()); println("paused"); gate.release(Text("resumed")); println("paused again"); gate.reject()
            }
            """, expected: "Text(value=sync)\nText(value=reference)\nText(value=made)\nText(value=number)\nnull\nText(value=some)\nMaybe(value=null)\nMaybe(value=null)\nArrayValue(value=[1, 2])\nBox(value=42)\nBox(value=null)\npaused\n22\nText(value=resumed)\npaused again\nfailed\nfinally\nText(value=done)\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m14SuspendReferenceInterfacesAndValueMembers(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            @JvmInline value class Text(val value: String)
            interface Echo { suspend fun echo(v: Text): Text }
            class Normal: Echo { override suspend fun echo(v: Text): Text = v }
            @JvmInline value class Own(val value: Long): Echo {
                override suspend fun echo(v: Text): Text = v
                suspend fun get(v: Text = Text("member")): Text = v
            }
            inline fun save(v: Text, noinline block: (Text) -> Text): () -> Text = { block(v) }
            inline fun cross(v: Text, crossinline block: (Text) -> Text): () -> Text = { block(v) }
            suspend fun main() {
                val normal: Echo = Normal(); val own: Echo = Own(9L)
                println(normal.echo(Text("normal"))); println(own.echo(Text("own")))
                println(Own(7L).get()); println(save(Text("saved")) { it }()); println(cross(Text("cross")) { it }())
            }
            """, expected: "Text(value=normal)\nText(value=own)\nText(value=member)\nText(value=saved)\nText(value=cross)\n", mode: mode, root: root)
        }
    }

    @Test
    func m14JavaAndKotlinInlineSuspendConsumers() throws {
        try withWorkspace { root in
            let result = try compile("""
            package api
            import kotlin.coroutines.*
            @JvmInline value class V(val value: Int)
            @JvmInline value class Text(val value: String)
            @JvmInline value class Box<T>(val value: T)
            inline fun apply(v: V = V(21), block: (V) -> V = { it }): V = block(v)
            inline fun guard(v: V, block: (V) -> V): V { try { return block(v) } finally { println("guard") } }
            inline fun <T> identity(v: Box<T>): Box<T> = v
            suspend fun echo(v: V = V(42)): V = v
            suspend fun text(v: Text = Text("default")): Text = v
            suspend fun make(): Text = Text("made")
            suspend fun fromInt(n: Int = 1): Text = Text("number")
            suspend fun <T> generic(v: Box<T>): Box<T> = v
            class Gate {
                var pending: Continuation<Text>? = null
                suspend fun await(v: Text): Text = suspendCoroutine { pending = it }
                fun release(v: Text) { pending!!.resume(v) }
            }
            @JvmName("javaV") suspend fun javaV(v: V): V = v
            @JvmName("javaText") suspend fun javaText(v: Text): Text = v
            """, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let jar = root.appendingPathComponent("hello.jar").path, runtime = try m11Runtime()
            try """
            package consumer
            import api.*
            import kotlin.coroutines.*
            fun early(): V { apply(V(7)) { return it }; return V(0) }
            fun guarded(): V { guard(V(8)) { return it }; return V(0) }
            fun main() {
                println(apply()); println(apply(V(20)) { V(it.value + 2) }); println(early()); println(guarded()); println(identity(Box("generic")))
                val gate = Gate()
                val work: suspend () -> Text = {
                    println(echo()); println(echo(V(21))); println(make()); println(fromInt()); println(text()); println(text(Text("some"))); println(generic(Box(42)))
                    val value = gate.await(Text("ignored")); println(value); Text("complete")
                }
                work.startCoroutine(object: Continuation<Text> {
                    override val context: CoroutineContext = EmptyCoroutineContext
                    override fun resumeWith(result: Result<Text>) { println(result.getOrThrow()) }
                })
                println("paused"); gate.release(Text("resume"))
            }
            """.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-cp", jar + ":" + runtime, "-d", "consumer.jar"], root: root)
            for cp in [jar + ":" + runtime, runtime + ":" + jar] {
                #expect(try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + cp, "consumer.ConsumerKt"]).stdout == "V(value=21)\nV(value=22)\nV(value=7)\nguard\nV(value=8)\nBox(value=generic)\nV(value=42)\nV(value=21)\nText(value=made)\nText(value=number)\nText(value=default)\nText(value=some)\nBox(value=42)\npaused\nText(value=resume)\nText(value=complete)\n")
            }
            try """
            public class JavaConsumer {
                public static void main(String[] args) {
                    kotlin.coroutines.Continuation<Object> completion = new kotlin.coroutines.Continuation<Object>() {
                        public kotlin.coroutines.CoroutineContext getContext() { return kotlin.coroutines.EmptyCoroutineContext.INSTANCE; }
                        public void resumeWith(Object result) { throw new AssertionError("Unexpected suspension"); }
                    };
                    Object v = api.HelloKt.javaV(42, completion);
                    Object text = api.HelloKt.javaText("raw", completion);
                    System.out.println(v); System.out.println(v.getClass().getName());
                    System.out.println(text); System.out.println(text.getClass().getName());
                }
            }
            """.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", jar + ":" + runtime, "JavaConsumer.java"], root: root)
            #expect(try java(["-cp", root.path + ":" + jar + ":" + runtime, "JavaConsumer"]).stdout == "V(value=42)\napi.V\nraw\njava.lang.String\n")
        }
    }
}
#endif
