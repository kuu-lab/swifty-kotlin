import Testing

// End-to-end (compiled and run) counterpart of the KIR-structural checks in
// CompilerCoreTests/Lowering/LoweringPassRegressionTests+ClassStringConversion.swift.
// A class's own overridden toString() must be called when the value is
// stringified through the Any-erased `+`/string-template funnel, not just
// when toString() is called directly -- see that file's header comment for
// the full root-cause writeup.
extension BundledStdlibExecutionTests {
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
