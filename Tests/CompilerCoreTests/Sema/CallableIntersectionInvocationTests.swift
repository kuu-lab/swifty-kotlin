@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CallableIntersectionInvocationTests {
    @Test
    func functionTypeRemainsCallableAfterKFunctionCast() throws {
        let ctx = makeContextFromSource("""
        fun render(value: Boolean): String = value.toString()
        fun applyOp(op: (Int) -> Int): Int = op(1)
        fun main() {
            val reference: (Boolean) -> Any = ::render
            val reflected = reference as kotlin.reflect.KFunction<*>
            val result = reference(true)
            val name = reflected.name

            val higherOrder: ((Int) -> Int) -> Int = ::applyOp
            val higherReflected = higherOrder as kotlin.reflect.KFunction<*>
            val number = higherOrder { it + 1 }
            val higherName = higherReflected.name
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        """
        fun render(value: Boolean): String = value.toString()
        fun test() {
            val reference: (Boolean) -> String = ::render
            val reflected = reference as kotlin.reflect.KFunction<*>
            reference(1)
        }
        """,
        """
        fun test(value: Any) {
            val reflected = value as kotlin.reflect.KFunction<*>
            value(1)
        }
        """,
    ])
    func rejectsInvalidInvocationAfterCast(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Expected rejection: \(source)")
    }
}
