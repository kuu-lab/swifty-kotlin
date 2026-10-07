#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSafeCallLambdaArgumentTests {

    @Test
    func nullablePrimitiveSafeCallLambdaArgumentsAreUnboxed() throws {
        let source = """
        fun implicit(idx: Int?): Char? = idx?.let { "abcd".get(it) }
        fun explicit(idx: Int?): Char? = idx?.let { index -> "abcd".get(index) }
        fun also(idx: Int?) = idx?.also { "abcd".get(it) }

        fun main() {
            println(implicit(2))
            println(explicit(2))
            println(also(2))
            println(implicit(null))
            println(explicit(null))
            println(also(null))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SafeCallLambdaPrimitiveArgument",
            expected: "c\nc\n2\nnull\nnull\nnull\n"
        )
    }
}
#endif
