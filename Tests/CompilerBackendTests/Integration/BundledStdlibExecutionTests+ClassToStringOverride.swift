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
            """
            @JvmInline value class VC(val v: Int)
            @JvmInline value class VC2(val v: Int) { override fun toString() = "custom$v" }
            @JvmInline value class WS(val s: String)
            @JvmInline value class Meters(val v: Double)
            @JvmInline value class Maybe(val v: Int?)
            class Outer {
                @JvmInline value class Nested(val n: Int)
            }
            data class Holder(val value: VC)
            fun main() {
                println(VC(5))
                println(VC(5).toString())
                println(VC2(5))
                println(WS("abc"))
                println(listOf(VC(1), VC(2)))
                println("template=${VC(6)}")
                val erased: Any = VC(7)
                println(erased.toString())
                println("$erased")
                println(Meters(1.5))
                println(Maybe(null))
                println(Maybe(9))
                println(Outer.Nested(8))
                println(Holder(VC(10)))
                println(VC(5) == VC(5))
                println(VC(5).hashCode())
            }
            """,
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
}
