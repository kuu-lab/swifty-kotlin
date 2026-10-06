#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendCompareValuesByImplicitSelectorsTests {
    @Test(arguments: [true, false])
    func implicitSelectorsResolve(allowDefaultStdlibLibrary: Bool) throws {
        let source = """
        fun main() {
            println(compareValuesBy(1, 2, { it }, { it }))
            println(compareValuesBy("a", "b", { it.length }, { it }))
            println(compareValuesBy(1, 2, { it }, { it }, { it }))
            println(compareValuesBy(1, 2, { x: Int -> x }, { it }))
            println(compareValuesBy(1, 2, { it }, { x: Int -> x }))
            println(compareValuesBy(1, 2, { it }, { it }, { it }, { it }))
            println(compareValuesBy(1, 2, { it }))
            println(compareValuesBy(1, 2, reverseOrder<Int>()) { it })
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "CompareValuesByImplicitSelectors",
            expected: "-1\n-1\n-1\n-1\n-1\n-1\n-1\n1\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
#endif
