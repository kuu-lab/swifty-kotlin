@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct MemberValReassignmentTests {
    @Test
    func readonlyCompanionAndInstancePropertiesRejectAssignment() throws {
        let source = """
        class Number {
            val value: Int = 0
            companion object { val ZERO: Number = Number() }
        }
        fun probe(number: Number) {
            Number.ZERO = Number()
            Number.Companion.ZERO = Number()
            number.value = 1
        }
        class Consumer() {
            init { Number.ZERO = Number() }
            constructor(number: Number): this() { Number.Companion.ZERO = number }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            do {
                try runSema(ctx)
            } catch {
                // Require reassignment diagnostics rather than any pipeline failure.
            }
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 5, "\(errors)")
            #expect(errors.allSatisfy {
                $0.code == "KSWIFTK-SEMA-0014" && $0.message == "Val cannot be reassigned."
            })
        }
    }

    @Test
    func mutableWritesAndValInitializationRemainAllowed() throws {
        let source = """
        class Number {
            val value: Int
            var mutable: Int = 0
            init { this.value = 7; this.mutable = 8 }
            companion object { var current: Number = Number() }
        }
        fun probe(number: Number) {
            Number.current = Number()
            Number.Companion.current = Number()
            number.mutable = 1
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }
}
