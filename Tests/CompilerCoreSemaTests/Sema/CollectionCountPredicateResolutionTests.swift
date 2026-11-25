@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CollectionCountPredicateResolutionTests {
    @Test(arguments: [
        "values.count { it + 1 }",
        "values.count(1)",
        "values.count({ true }, { false })",
    ])
    func invalidCountPredicateIsRejected(expression: String) throws {
        let source = """
        fun main() {
            val values: Collection<Int> = listOf(0, 1, 2)
            println(\(expression))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(!errors.isEmpty)
            #expect(errors.contains {
                $0.code.hasPrefix("KSWIFTK-SEMA-") || $0.code.hasPrefix("KSWIFTK-TYPE-")
            })
        }
    }
}
