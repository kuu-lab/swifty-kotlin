@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Testing

@Suite(.serialized)
struct SamConstructorComparatorDispatchTests {
    @Test
    func callableReferenceComparatorDispatchesInsideSortedWith() throws {
        try compileAndRunKotlin(
            try diffCaseSource("sam_constructor_callable_ref.kt", file: #filePath),
            expectedOutput: "-2\n-2\n98\nv=42\n[1, 3, 5]\n[2, 4, 9]\n",
            moduleName: "KUU2407SamConstructorCallableReference",
            expectedStderr: ""
        )
    }

    @Test
    func functionValueComparatorDispatchesInsideSortedWith() throws {
        try compileAndRunKotlin(
            try diffCaseSource("sam_constructor_function_value.kt", file: #filePath),
            expectedOutput: "v=42\n-2\n[2, 4, 9]\n",
            moduleName: "KUU2407SamConstructorFunctionValue",
            expectedStderr: ""
        )
    }
}
