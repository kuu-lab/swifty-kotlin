#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct DoWhileNewlineInForTests {
    @Test
    func doWhileConditionReadsAssignmentInsideForBody() throws {
        let source = """
        class Cursor {
            operator fun hasNext(): Boolean = false
            operator fun next(): Int = 0
        }
        class Values { operator fun iterator(): Cursor = Cursor() }

        fun main() {
            for (c in Values()) {
                var input: Int
                do {
                    input = 1
                }
                while (input != 2)
                input
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)

            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors)")
        }
    }
}
#endif
