#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m13ArrayValueClasses(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            @JvmInline value class Numbers(val value: IntArray)
            @JvmInline value class Optional(val value: IntArray?)
            @JvmInline value class Items<T>(val value: Array<T>)
            fun echo(v: Numbers): Numbers = v
            fun optional(v: Numbers?): Numbers? = v
            fun main() {
                val raw = intArrayOf(1, 2)
                val first = Numbers(raw); val second = Numbers(raw)
                println(echo(first)); println(first == second); println(first == Numbers(intArrayOf(1, 2)))
                println(first.hashCode()); println(optional(null)); println(optional(first))
                raw[0] = 3; println(first); println(first.hashCode())
                val none = Optional(null); println(none); println(none.hashCode()); println(none == Optional(null))
                val items = Items(arrayOf("a", "b")); val values: Array<String> = items.value
                println(items); println(values[1]); println(items.hashCode())
                val read = { first.value[0] }; println(read())
            }
            """, expected: "Numbers(value=[1, 2])\ntrue\nfalse\n994\nnull\nNumbers(value=[1, 2])\nNumbers(value=[3, 2])\n1056\nOptional(value=null)\n0\ntrue\nItems(value=[a, b])\nb\n4066\n3\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m13NestedValueClasses(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            @JvmInline value class I(val value: Int)
            @JvmInline value class S(val value: String)
            @JvmInline value class N(val value: String?)
            @JvmInline value class Outer(val value: I)
            @JvmInline value class Deep(val value: Outer)
            @JvmInline value class Text(val value: S)
            @JvmInline value class Maybe(val value: S?)
            @JvmInline value class NullText(val value: N)
            @JvmInline value class Boxed(val value: N?)
            fun echo(v: Deep): Deep = v
            fun text(v: Text?): Text? = v
            fun maybe(v: Maybe?): Maybe? = v
            fun main() {
                val v = Deep(Outer(I(21))); println(echo(v)); println(v.value.value.value)
                println(v.hashCode()); println(v == Deep(Outer(I(21))))
                val any: Any = v; println(any); println(any == v)
                println(text(null)); println(text(Text(S("ok"))))
                println(maybe(null)); println(maybe(Maybe(null))); println(maybe(Maybe(S("yes"))))
                println(NullText(N(null))); println(Boxed(null)); println(Boxed(N(null)))
                val read = { v.value.value.value }; println(read())
            }
            """, expected: "Deep(value=Outer(value=I(value=21)))\n21\n21\ntrue\nDeep(value=Outer(value=I(value=21)))\ntrue\nnull\nText(value=S(value=ok))\nnull\nMaybe(value=null)\nMaybe(value=S(value=yes))\nNullText(value=N(value=null))\nBoxed(value=null)\nBoxed(value=N(value=null))\n21\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m13ValueConstructorsDefaultsAndInitialization(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            var events = 0
            fun mark(n: Int): Int { events = events * 10 + n; return n }
            @JvmInline value class V(val value: Int = mark(10)) {
                init { events = events * 10 + 1 }
                constructor(s: String): this(mark(if (s == "abc") 3 else 2)) { events = events * 10 + 2 }
                constructor(b: Boolean, x: Int = mark(20)): this(if (b) x else mark(30)) { events = events * 10 + 3 }
                constructor(l: Long, s: String = "ok"): this(s) { events = events * 10 + 4 }
                constructor(n: Int, b: Boolean): this(if (b) n else 0) { events = events * 10 + 5 }
            }
            @JvmInline value class Outer(val value: V = V()) {
                constructor(s: String): this(V(s))
            }
            fun main() {
                println(V()); println(events); events = 0
                println(V("abc")); println(events); events = 0
                println(V(true)); println(events); events = 0
                println(V(false, x = mark(4))); println(events); events = 0
                println(V(1L)); println(events); events = 0
                println(V(8, true)); println(events); events = 0
                println(Outer()); println(events); events = 0
                val v = V(7); val any: Any = v; println(any); println(events)
                println(Outer("test").value.value)
                val ctor: (String) -> V = ::V; println(ctor("abcde"))
            }
            """, expected: "V(value=10)\n101\nV(value=3)\n312\nV(value=20)\n2013\nV(value=30)\n7013\nV(value=2)\n2124\nV(value=8)\n15\nOuter(value=V(value=10))\n101\nV(value=7)\n1\n2\nV(value=2)\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m13WideGenericAndMultipleMaskConstructors(mode: EmitMode) throws {
        try withWorkspace { root in
            let params = (0..<33).map { "p\($0): Int = \($0)" }.joined(separator: ", ")
            try runM11("""
            @JvmInline value class Many(val value: Int) {
                constructor(tag: Long, \(params)): this(p0 + p31 + p32)
            }
            @JvmInline value class Wide(val value: Long = 9L) {
                constructor(a: Int, b: Long = a.toLong(), c: Long = b + 2L): this(c)
            }
            @JvmInline value class Generic<T>(val value: T) {
                constructor(values: List<T>, pick: Boolean = true): this(values[0])
            }
            class Holder {
                @JvmInline value class Nested(val value: Int) {
                    constructor(b: Boolean): this(if (b) 9 else 8)
                }
            }
            var count = 0
            fun fail(): Int { throw IllegalStateException("default") }
            @JvmInline value class Checked(val value: Int = fail()) { init { count++ } }
            fun main() {
                println(Many(1L, p31 = 100)); println(Wide()); println(Wide(4)); println(Wide(4, c = 20L))
                println(Generic<String>(listOf("hi")).value); println(Holder.Nested(true))
                try { Checked() } catch (e: IllegalStateException) { println(e.message) }
                println(count); val checked: Any = Checked(7); println(checked); println(count)
            }
            """, expected: "Many(value=132)\nWide(value=9)\nWide(value=6)\nWide(value=20)\nhi\nNested(value=9)\ndefault\n0\nChecked(value=7)\n1\n", mode: mode, root: root)
        }
    }

    @Test
    func m13JavaAndKotlinValueConstructorConsumers() throws {
        try withWorkspace { root in
            let result = try compile("""
            package abi
            @JvmInline value class I(val value: Int = 11) { constructor(s: String, offset: Int = 1): this((if (s == "abc") 3 else 4) + offset) }
            @JvmInline value class Outer(val value: I = I())
            @JvmInline value class Numbers(val value: IntArray = intArrayOf(4, 5))
            @JvmInline value class Items<T>(val value: Array<T>) { fun first(): T = value[0] }
            @JvmInline value class Values<T>(val value: List<T>)
            @JvmInline value class Nested<T>(val value: Values<T>)
            @JvmName("javaNested") fun nested(v: Nested<String>): Nested<String> = v
            @JvmName("javaEcho") fun echo(v: Outer): Outer = v
            """, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let jar = root.appendingPathComponent("hello.jar").path, runtime = try m11Runtime()
            try """
            import abi.*
            fun main() {
                println(I()); println(I("abc")); println(I("abc", 2)); println(Outer()); println(Numbers())
                println(echo(Outer(I(21))).value.value)
                println(nested(Nested(Values(listOf("nested")))).value.value[0])
                val items = Items(arrayOf("a", "b")); val raw: Array<String> = items.value; println(raw[1])
                val ctor = I::class.constructors.first { it.parameters.size == 2 }
                println(ctor.parameters[1].isOptional); println(ctor.call("abcd", 3))
                println(Outer::class.constructors.first().call(I(42)))
            }
            """.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-cp", jar + ":" + runtime, "-d", "consumer.jar"], root: root)
            for cp in [jar + ":" + runtime, runtime + ":" + jar] {
                #expect(try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + cp, "ConsumerKt"]).stdout == "I(value=11)\nI(value=4)\nI(value=5)\nOuter(value=I(value=11))\nNumbers(value=[4, 5])\n21\nnested\nb\ntrue\nI(value=7)\nOuter(value=I(value=42))\n")
            }
            try """
            public class Consumer {
                public static void main(String[] args) throws Exception {
                    System.out.println(abi.HelloKt.javaEcho(21));
                    System.out.println(abi.Outer.class.getDeclaredField("value").getType().getName());
                    System.out.println(abi.I.class.getMethod("constructor-impl$default", int.class, int.class, kotlin.jvm.internal.DefaultConstructorMarker.class).invoke(null, 0, 1, null));
                    System.out.println(abi.I.class.getMethod("constructor-impl$default", String.class, int.class, int.class, kotlin.jvm.internal.DefaultConstructorMarker.class).invoke(null, "abc", 0, 2, null));
                    System.out.println(abi.Numbers.class.getMethod("constructor-impl$default", int[].class, int.class, kotlin.jvm.internal.DefaultConstructorMarker.class).getReturnType().getName());
                    System.out.println(abi.Items.class.getDeclaredField("value").getGenericType().getTypeName());
                    System.out.println(abi.Items.class.getMethod("constructor-impl", Object[].class).getGenericReturnType().getTypeName());
                    System.out.println(abi.Items.class.getMethod("first-impl", Object[].class).getGenericParameterTypes()[0].getTypeName());
                    System.out.println(abi.Nested.class.getDeclaredField("value").getGenericType().getTypeName());
                    System.out.println(abi.Nested.class.getMethod("constructor-impl", java.util.List.class).getGenericReturnType().getTypeName());
                    System.out.println(abi.HelloKt.class.getMethod("javaNested", java.util.List.class).getGenericReturnType().getTypeName());
                }
            }
            """.write(to: root.appendingPathComponent("Consumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", jar + ":" + runtime, "Consumer.java"], root: root)
            #expect(try java(["-cp", root.path + ":" + jar + ":" + runtime, "Consumer"]).stdout == "21\nint\n11\n4\n[I\nT[]\njava.lang.Object[]\njava.lang.Object[]\njava.util.List<T>\njava.util.List<T>\njava.util.List<java.lang.String>\n")
        }
    }
}
#endif
