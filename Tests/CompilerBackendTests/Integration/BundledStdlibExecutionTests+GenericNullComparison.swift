import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testGenericNullComparisonsRespectNullableTypeArguments(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            class NullChecks<T> {
                fun equal(value: T): Boolean = value == null
                fun unequal(value: T): Boolean = value != null
                fun identical(value: T): Boolean = null === value
                fun distinct(value: T): Boolean = null !== value
            }
            fun main() {
                val checks = NullChecks<Long?>()
                println(checks.equal(null))
                println(checks.unequal(null))
                println(checks.identical(null))
                println(checks.distinct(null))
                println(checks.equal(Long.MIN_VALUE))
                println(checks.unequal(Long.MIN_VALUE))
                println(checks.identical(Long.MIN_VALUE))
                println(checks.distinct(Long.MIN_VALUE))
                println(NullChecks<String?>().equal(null))
                println(NullChecks<String?>().equal("a"))
            }
            """,
            expectedOutput: "true\nfalse\ntrue\nfalse\nfalse\ntrue\nfalse\ntrue\ntrue\nfalse\n",
            moduleName: "KUU1897GenericNullComparison",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
