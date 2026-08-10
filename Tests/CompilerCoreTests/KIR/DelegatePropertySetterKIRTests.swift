#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Tests for delegate property setter rewriting and lowering pass recording.
@Suite
struct DelegatePropertySetterKIRTests {
    // MARK: - Setter Rewrite: Observable / Vetoable

    @Test func testObservableAndVetoableSettersRewriteToSetValueCalls() throws {
        let sources = [
            """
            package sample0

            import kotlin.properties.Delegates

            var name: String by Delegates.observable("initial") { prop, old, new ->
                println("changed")
            }

            fun main0() {
                name = "updated"
                println(name)
            }
            """,
            """
            package sample1

            import kotlin.properties.Delegates

            var count: Int by Delegates.vetoable(0) { prop, old, new ->
                new >= 0
            }

            fun main1() {
                count = 5
                println(count)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            let diagnosticMessages = ctx.diagnostics.diagnostics.map(\.message)
            #expect(
                !(ctx.diagnostics.hasError),
                "observable/vetoable setters should compile without errors: \(diagnosticMessages)"
            )

            let module = try #require(ctx.kir)

            let observableBody = try findKIRFunctionBody(
                named: "main0", in: module, interner: ctx.interner
            )
            let observableCallees = extractCallees(from: observableBody, interner: ctx.interner)
            #expect(
                observableCallees.contains("kk_observable_set_value"),
                "Should emit kk_observable_set_value, got: \(observableCallees)"
            )

            let vetoableBody = try findKIRFunctionBody(
                named: "main1", in: module, interner: ctx.interner
            )
            let vetoableCallees = extractCallees(from: vetoableBody, interner: ctx.interner)
            #expect(
                vetoableCallees.contains("kk_vetoable_set_value"),
                "Should emit kk_vetoable_set_value, got: \(vetoableCallees)"
            )
        }
    }

    // MARK: - StdlibDelegateLowering Pass Is Recorded

    @Test func testStdlibDelegateLoweringPassIsRecordedInModule() throws {
        let source = """
        val x by lazy { 42 }
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            #expect(
                module.executedLowerings.contains("StdlibDelegateLowering"),
                "Should be recorded: \(module.executedLowerings)"
            )
        }
    }
}
#endif
