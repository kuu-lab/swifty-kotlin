import TestStdlibCache
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testFunctionValueToStringMatchesReflectiveFunctionType(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        try compileAndRunKotlin(
            """
            fun check(expected: String, obj: Any?) {
                val actual = obj.toString()
                if (actual != expected) throw AssertionError("Expected: $expected, actual: $actual")
            }

            fun foo() = Unit

            fun capturedFunction(value: Int): () -> Int = { value }

            fun <T> genericFunctionDescription(): String = { value: T -> value }.toString()

            fun main() {
                check("() -> kotlin.Unit", {})
                check("() -> kotlin.Int", { 42 })
                check("() -> kotlin.Int", capturedFunction(42))
                check("(kotlin.Int, kotlin.Int) -> kotlin.Unit", { _: Int, _: Int -> })
                check("kotlin.Int.() -> kotlin.Unit", fun Int.() {})
                check("fun foo(): kotlin.Unit", ::foo)
                check("(T) -> T", genericFunctionDescription<String>())
                println("OK")
            }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU3581FunctionValueToString",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
