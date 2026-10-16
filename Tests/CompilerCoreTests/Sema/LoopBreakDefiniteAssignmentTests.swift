#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct LoopBreakDefiniteAssignmentTests {
    @Test
    func acceptsAssignmentOnEveryBreakExitFromDoWhileTrue() throws {
        try check("""
        var field: Int = 0
        fun next(): Int {
            return ++field
        }
        fun box(): String {
            val task: String
            do {
                if (next() % 2 == 0) {
                    task = "OK"
                    break
                }
            } while (true)
            return task
        }
        """, expectedErrorCode: nil)
    }

    @Test
    func acceptsAssignmentOnBothConditionalBreakExits() throws {
        try check("""
        fun shouldBreak(): Boolean = true
        fun box(): String {
            val task: String
            do {
                if (shouldBreak()) {
                    task = "OK"
                    break
                } else {
                    task = "OK"
                    break
                }
            } while (true)
            return task
        }
        """, expectedErrorCode: nil)
    }

    @Test
    func rejectsBreakExitWithoutAssignment() throws {
        try check("""
        fun shouldBreak(): Boolean = true
        fun box(): String {
            val task: String
            do {
                if (shouldBreak()) break
                task = "OK"
            } while (true)
            return task
        }
        """, expectedErrorCode: "KSWIFTK-SEMA-0031")
    }

    @Test
    func rejectsNormalDoWhileExitWithoutAssignment() throws {
        try check("""
        fun shouldBreak(): Boolean = true
        fun box(): String {
            val task: String
            do {
                if (shouldBreak()) {
                    task = "OK"
                    break
                }
            } while (shouldBreak())
            return task
        }
        """, expectedErrorCode: "KSWIFTK-SEMA-0031")
    }

    @Test
    func breakAssignmentDoesNotPermitValReassignment() throws {
        try check("""
        fun box(): String {
            val task: String
            do {
                task = "OK"
                break
            } while (true)
            task = "again"
            return task
        }
        """, expectedErrorCode: "KSWIFTK-SEMA-0014")
    }

    private func check(_ source: String, expectedErrorCode: String?) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            if let expectedErrorCode {
                #expect(errors.contains { $0.code == expectedErrorCode }, "\(source): \(errors)")
            } else {
                #expect(errors.isEmpty, "\(source): \(errors)")
            }
        }
    }
}
#endif
