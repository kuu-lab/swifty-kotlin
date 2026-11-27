import Testing

@Suite
struct NullableULongValueClassTypeChecksTests {
    @Test
    func boxedValueClassDoesNotPassUnderlyingULongTypeCheck() throws {
        try compileAndRunKotlin(
            """
            @JvmInline value class Counter(val raw: ULong)

            fun boxed(counter: Counter): Any = counter

            fun main() {
                val value: Any = boxed(Counter(7uL))
                val primitive: Any = 7uL
                println(value is ULong)
                println(value is Counter)
                println((value as? ULong) == null)
                println((value as? Counter)?.raw)
                println(primitive is ULong)
                println((primitive as? ULong)?.toString())
            }
            """,
            expectedOutput: "false\ntrue\ntrue\n7\ntrue\n7\n",
            moduleName: "NullableULongValueClassTypeChecks"
        )
    }
}
