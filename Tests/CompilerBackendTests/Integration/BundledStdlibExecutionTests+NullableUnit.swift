import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testNullableUnitValues(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.typeOf

            class UnitReceiver { fun touch() {} }

            fun emptyUnit(): Unit? = null
            fun presentUnit(): Unit? = Unit
            fun main() {
                var unit: Unit? = null
                println(unit)
                println(emptyUnit())
                println(unit?.toString())
                println(unit ?: Unit)
                val erased: Any? = unit
                println(erased)
                unit = Unit
                println(unit)
                println(unit?.toString())
                println(presentUnit())
                val boxed: Any? = unit
                println(boxed)
                unit = null
                println(unit)
                val absent: UnitReceiver? = null
                val present: UnitReceiver? = UnitReceiver()
                println(absent?.touch())
                println(present?.touch())
                val callback: () -> Unit? = { null }
                println(callback())
                println(typeOf<Unit?>().isMarkedNullable)
                println(typeOf<Unit>().isMarkedNullable)
            }
            """,
            expectedOutput: "null\nnull\nnull\nkotlin.Unit\nnull\nkotlin.Unit\nkotlin.Unit\nkotlin.Unit\nkotlin.Unit\nnull\nnull\nkotlin.Unit\nnull\ntrue\nfalse\n",
            moduleName: "NullableUnit",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
