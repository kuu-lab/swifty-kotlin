#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NegatedBooleanContractTests {
    @Test
    func normalAndConditionalReturnsUseTheFalseArgumentBranch() throws {
        let declarations = """
        import kotlin.contracts.*
        @OptIn(ExperimentalContracts::class)
        fun reject(actual: Boolean) {
            contract { returns() implies (!actual) }
            if (actual) throw IllegalArgumentException()
        }
        @OptIn(ExperimentalContracts::class)
        fun rejected(actual: Boolean): Boolean {
            contract { returns(true) implies (!actual) }
            return !actual
        }
        """
        let positive = [
            "reject(x == null); println(x.length)",
            "reject(actual = x == null); println(x.length)",
            "if (rejected(x == null)) println(x.length)",
            "if (!rejected(x == null)) {} else println(x.length)",
        ]
        let negative = [
            "rejected(x == null); println(x.length)",
            "if (!rejected(x == null)) println(x.length)",
            "if (rejected(x == null)) {} else println(x.length)",
        ]
        let sources = (positive + negative).enumerated().map { index, body in
            "package negatedContract\(index)\n" + declarations + "\nfun probe(x: String?) { \(body) }"
        }
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for path in paths.prefix(positive.count) {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(errors.isEmpty, "\(path): \(errors)")
            }
            for path in paths.dropFirst(positive.count) {
                assertHasDiagnostic("KSWIFTK-SEMA-0026", in: diagnosticsForPath(path, in: ctx))
            }
        }
    }
}
#endif
