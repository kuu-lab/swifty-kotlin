#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CodegenBackendNameBasedDestructuringTests {
    @Test
    func discardedNamedPropertyIsStillEvaluated() throws {
        try compileAndRunKotlin(
            diffCaseSource("name_based_destructuring_underscore_getter.kt"),
            expectedOutput: "1\n",
            moduleName: "NameBasedDestructuringDiscardedProperty"
        )
    }
}
#endif
