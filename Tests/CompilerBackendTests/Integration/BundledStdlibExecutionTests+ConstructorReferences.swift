import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func typedConstructorReferences(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            class Gen<T>(val x: T)
            fun main() {
                val g: (Int) -> Gen<Int> = ::Gen
                println(g(5).x)
                val p: (Int, String) -> Pair<Int, String> = ::Pair
                println(p(1, "a").second)
                val t: (Int, Int, Int) -> Triple<Int, Int, Int> = ::Triple
                println(t(1, 2, 3).third)
                val e: (String) -> IllegalStateException = ::IllegalStateException
                println(e("m").message)
                val ia: (Int) -> IntArray = ::IntArray
                val values = ia(2)
                println(values.size)
                println(values[0])
                values[1] = 7
                println(values[1])
                val erased: Any = values
                println(erased is IntArray)
                println(erased is LongArray)
                try {
                    ia(-1)
                } catch (e: NegativeArraySizeException) {
                    println("negative size")
                }
            }
            """,
            expectedOutput: "5\na\n3\nm\n2\n0\n7\ntrue\nfalse\nnegative size\n",
            moduleName: "KUU1276ConstructorReferences",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
