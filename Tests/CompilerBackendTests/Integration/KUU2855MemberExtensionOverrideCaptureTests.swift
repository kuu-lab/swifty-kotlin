import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testMemberExtensionOverrideCallsCapturedReceiverFunctionParameter() throws {
        try compileAndRunKotlin(
            """
            interface Ctx { val y: String }
            interface Codec<T> { fun Ctx.decode(): T? }
            fun <T> codec(decode: Ctx.() -> T?): Codec<T> = object : Codec<T> {
                override fun Ctx.decode(): T? = decode()
            }
            fun main() {
                val t: Codec<String> = codec({ y })
                val ctx = object : Ctx { override val y = "OK" }
                println(with(t) { ctx.decode() })
            }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU2855MemberExtensionOverrideCapture"
        )
    }
}
