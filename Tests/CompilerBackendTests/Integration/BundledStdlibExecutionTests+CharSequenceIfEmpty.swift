import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testCharSequenceIfEmptyAvoidsGetWithStdlibArtifact() throws {
        try assertCharSequenceIfEmpty(allowDefaultStdlibLibrary: true)
    }

    @Test
    func testCharSequenceIfEmptyAvoidsGetWithSourceInjection() throws {
        try assertCharSequenceIfEmpty(allowDefaultStdlibLibrary: false)
    }

    private func assertCharSequenceIfEmpty(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            class CountingCharSequence(private val value: String) : CharSequence {
                var lengthReads: Int = 0
                var getCalls: Int = 0

                override val length: Int
                    get() {
                        lengthReads++
                        return value.length
                    }

                override fun get(index: Int): Char {
                    getCalls++
                    return value[index]
                }

                override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
                    value.substring(startIndex, endIndex)
            }

            fun choose(value: CharSequence, defaultValue: () -> CharSequence): CharSequence =
                value.ifEmpty(defaultValue)

            fun main() {
                val nonEmpty = CountingCharSequence("text")
                val retained = choose(nonEmpty) { CountingCharSequence("fallback") }
                println(retained === nonEmpty)
                println(nonEmpty.lengthReads)
                println(nonEmpty.getCalls)

                val empty = CountingCharSequence("")
                val fallback = CountingCharSequence("replacement")
                val replaced = choose(empty) { fallback }
                println(replaced === fallback)
                println(empty.lengthReads)
                println(empty.getCalls)

                val builder = StringBuilder("builder")
                println(choose(builder) { StringBuilder("fallback") } === builder)
                val emptyBuilder = StringBuilder()
                val builderFallback = StringBuilder("fallback")
                println(choose(emptyBuilder) { builderFallback } === builderFallback)
            }
            """,
            expectedOutput: "true\n1\n0\ntrue\n1\n0\ntrue\ntrue\n",
            moduleName: "CharSequenceIfEmptyLengthOnly",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
