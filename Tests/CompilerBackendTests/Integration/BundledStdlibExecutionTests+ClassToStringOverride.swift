import TestStdlibCache
import Testing

// End-to-end (compiled and run) counterpart of the KIR-structural checks in
// CompilerCoreTests/Lowering/LoweringPassRegressionTests+ClassStringConversion.swift.
// A class's own overridden toString() must be called when the value is
// stringified through the Any-erased `+`/string-template funnel, not just
// when toString() is called directly -- see that file's header comment for
// the full root-cause writeup.
extension BundledStdlibExecutionTests {
    // KUU-1254: cover both imported-artifact and source-injected stdlib paths.
    @Test(arguments: [true, false])
    func testValueClassSynthesizedToString(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("value_class_synthesized_to_string.kt", file: #filePath),
            expectedOutput:
                """
                VC(v=5)
                VC(v=5)
                custom5
                WS(s=abc)
                [VC(v=1), VC(v=2)]
                template=VC(v=6)
                VC(v=7)
                VC(v=7)
                Meters(v=1.5)
                Maybe(v=null)
                Maybe(v=9)
                Nested(n=8)
                Holder(value=VC(v=10))
                true
                5
                """ + "\n",
            moduleName: "KUU1254ValueClassToString",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    // KUU-599 regression: an imported generic collection HOF passes a boxed
    // value-class element through an erased callback ABI. Double must be
    // unboxed before the lambda reads its property, and a value class's
    // toString() must survive Any/collection boxing.
    @Test
    func testValueClassDoubleSurvivesErasedMapAndAnyToString() throws {
        try compileAndRunKotlin(
            """
            @JvmInline
            value class Meters(val v: Double) {
                override fun toString(): String = "${v}m"
            }

            @JvmInline
            value class Id(val raw: Int) {
                override fun toString(): String = "#$raw"
            }

            fun main() {
                println(listOf(Meters(1.0)).map { it.v })
                println(listOf(Meters(1.0)).map { it.v + 1 })
                println(listOf(Meters(1.0), Meters(2.0)).map { it.v + 1 })
                println(listOf(Id(2)).map { it.raw + 1 })
                println(listOf(Meters(1.0)).sumOf { it.v })
                println(listOf(Meters(1.0)))
                println(listOf(Id(1)).map { it })
                val any: Any = Id(3)
                println(any.toString())
                println("$any")
                println(Meters(1.0))
                println("${Id(4)}")
            }
            """,
            expectedOutput:
                """
                [1.0]
                [2.0]
                [2.0, 3.0]
                [3]
                1.0
                [1.0m]
                [#1]
                #3
                #3
                1.0m
                #4
                """ + "\n",
            moduleName: "KUU599ValueClassDouble"
        )
    }

    @Test
    func testClassConcatenationAndInterpolationCallOverriddenToString() throws {
        try compileAndRunKotlin(
            """
            class Foo(val x: Int) {
                override fun toString(): String = "Foo(" + x + ")"
            }
            fun main() {
                val f = Foo(1)
                println("concat=" + f)
                println("interp=$f")
            }
            """,
            expectedOutput: "concat=Foo(1)\ninterp=Foo(1)\n"
        )
    }

    @Test
    func testNullableClassConcatenationPrintsNullForActualNull() throws {
        try compileAndRunKotlin(
            """
            class Foo(val x: Int) {
                override fun toString(): String = "Foo(" + x + ")"
            }
            fun main() {
                val nonNull: Foo? = Foo(1)
                println("a=" + nonNull)
                val absent: Foo? = null
                println("b=" + absent)
            }
            """,
            expectedOutput: "a=Foo(1)\nb=null\n"
        )
    }

    // A base-typed receiver holding a derived instance must call the runtime
    // type's override via virtual dispatch, both through `+` concatenation
    // and through the println/print rewrite (ConsolePrintLoweringPass), which
    // had the same static-dispatch defect for an open-class-typed receiver.
    @Test
    func testPolymorphicClassToStringUsesVirtualDispatchInConcatAndPrintln() throws {
        try compileAndRunKotlin(
            """
            open class Animal {
                override fun toString(): String = "Animal"
            }
            class Dog : Animal() {
                override fun toString(): String = "Dog"
            }
            fun main() {
                val a: Animal = Dog()
                println("poly=" + a)
                println(a)
            }
            """,
            expectedOutput: "poly=Dog\nDog\n"
        )
    }

    @Test
    func testInheritedAndAnyErasedClassToStringUseOverrides() throws {
        try compileAndRunKotlin(
            """
            open class Base {
                override fun toString(): String = "Base!"
            }
            class Derived : Base()
            class Foo(val x: Int) {
                override fun toString(): String = "Foo(" + x + ")"
            }
            fun main() {
                val derived: Derived = Derived()
                println("derived=" + derived)
                println(derived)
                val erased: Any = Foo(1)
                println("any=" + erased)
                println("method=" + erased.toString())
            }
            """,
            expectedOutput: "derived=Base!\nBase!\nany=Foo(1)\nmethod=Foo(1)\n"
        )
    }

    // KUU-3230: a direct `x.toString()` on a class that inherits the
    // implementation is a vtable call rooted at the synthetic `Any.toString`
    // declaration. That slot returns a flat String aggregate, but the
    // root-most symbol links to the raw-handle runtime helper
    // (`kk_any_member_to_string`), so the indirect call used to be declared
    // `i64`-returning and miscalled the flat implementation (printing
    // `null`). Data classes inheriting final `toString`/`hashCode`/`equals`
    // hit the same path — they keep the inherited implementations instead of
    // regenerating them.
    @Test(arguments: [true, false])
    func testInheritedToStringVirtualCallUsesFlatStringABI(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        try compileAndRunKotlin(
            """
            open class Base {
                final override fun toString(): String = "OK"
                final override fun hashCode(): Int = 42
                final override fun equals(other: Any?): Boolean = false
            }
            data class DataClass(val field: String) : Base()

            abstract class Root {
                final override fun toString(): String = "ROOT"
            }
            abstract class Mid : Root()
            data class DeepChild(val field: String) : Mid()

            open class OpenBase {
                override fun toString(): String = "open-base"
            }
            data class OpenChild(val field: String) : OpenBase()

            class Plain : Base()

            fun main() {
                val d = DataClass("x")
                println(d.toString())
                println(d.hashCode())
                println(d.equals(d))
                println(DeepChild("x").toString())
                println(OpenChild("x").toString())
                println(Plain().toString())
            }
            """,
            expectedOutput: "OK\n42\nfalse\nROOT\nOpenChild(field=x)\nOK\n",
            moduleName: "KUU3230InheritedToString",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    // KUU-3197: an `object` (or class) inheriting `toString` from an open
    // superclass dispatches through a per-object vtable slot registered at
    // construction. The slot must carry the flat String-aggregate
    // implementation — the raw `kk_any_to_string_bridge_*` thunk belongs only
    // to the erased-Any stringify map, and storing it in the slot made the
    // flat indirect call read the bridge's single i64 handle as the flat
    // String aggregate, so the inherited `toString()` result was corrupt
    // instead of printing "K".
    @Test(arguments: [true, false])
    func testInheritedToStringVtableSlotUsesFlatABI(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        try compileAndRunKotlin(
            """
            object K : Code("K")
            open class Code(val x: String) { override fun toString() = x }
            class O { companion object: Code("O") }
            class Sub(val y: String) : Code(y)
            fun box() = O.toString() + K.toString()
            fun main() {
                println(box())
                println(K.toString())
                println(Sub("S").toString())
                println(Code("C").toString())
                val c: Code = Sub("P")
                println(c.toString())
            }
            """,
            expectedOutput: "OK\nK\nS\nC\nP\n",
            moduleName: "KUU3197ObjectSuperCtor",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    // KUU-3507: an object inheriting a superclass toString() must keep the
    // same result through println, explicit calls, and string interpolation.
    @Test
    func testInheritedObjectToStringAcrossStringPaths() throws {
        try compileAndRunKotlin(
            """
            open class Code(val x: String) {
                override fun toString() = "$x"
                fun foo(): String = x
            }
            object K : Code("K")
            object Own {
                override fun toString(): String = "Own"
            }
            fun main() {
                println(K)
                println(K.toString())
                println("$K")
                val r = K
                println(r.toString())
                println(K.x)
                println(K.foo())
                println(Own)
                println(Own.toString())
            }
            """,
            expectedOutput: "K\nK\nK\nK\nK\nK\nOwn\nOwn\n",
            moduleName: "KUU3507InheritedObjectToString"
        )
    }
}
