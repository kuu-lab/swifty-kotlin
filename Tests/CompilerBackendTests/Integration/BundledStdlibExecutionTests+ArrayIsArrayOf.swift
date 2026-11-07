import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testArrayIsArrayOfMatchesComponentAssignability() throws {
        try assertKotlinOutput(
            """
            inline fun <reified T : Any> checkReified(a: Array<*>): Boolean = a.isArrayOf<T>()

            fun viaWith(a: Array<*>): Boolean = with(a) { isArrayOf<Int>() }

            fun main() {
                val ints = arrayOf(1, 2)
                val strs = arrayOf("a", "b")
                val anys: Array<Any> = arrayOf<Any>(1, "x")
                println(ints.isArrayOf<Int>())
                println(ints.isArrayOf<String>())
                println(ints.isArrayOf<Number>())
                println(ints.isArrayOf<CharSequence>())
                println(ints.isArrayOf<Any>())
                println(strs.isArrayOf<String>())
                println(strs.isArrayOf<CharSequence>())
                println(anys.isArrayOf<Any>())
                println(anys.isArrayOf<Int>())
                println(viaWith(ints))
                println(viaWith(strs))
                val maybeInts: Array<Int>? = ints
                val noInts: Array<Int>? = null
                println(maybeInts?.isArrayOf<Int>())
                println(noInts?.isArrayOf<Int>())
                println(checkReified<Int>(ints))
                println(checkReified<String>(ints))
                val star: Array<*> = strs
                println(star.isArrayOf<CharSequence>())
                println(star.isArrayOf<Int>())
            }
            """,
            moduleName: "ArrayIsArrayOfComponentCheck",
            expected: "true\nfalse\ntrue\nfalse\ntrue\ntrue\ntrue\ntrue\nfalse\ntrue\nfalse\ntrue\nnull\ntrue\ntrue\ntrue\nfalse\n"
        )
    }
}
