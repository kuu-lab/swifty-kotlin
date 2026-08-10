#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// BUG-165: top-level property initializers are lowered under their own
/// function scopes (each restarting label allocation at 10000) and then
/// spliced into `main`.  Duplicated labels made codegen fold unrelated basic
/// blocks together, emitting instructions after a terminator and crashing
/// LLVM.
@Suite
struct TopLevelInitializerLabelKIRTests {
    private func mainLabelIDs(in source: String) throws -> [Int32] {
        var labels: [Int32] = []
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            #expect(!(ctx.diagnostics.hasError),
                    "source should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))")
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            labels = body.compactMap { instruction in
                if case let .label(id) = instruction { return id }
                return nil
            }
        }
        return labels
    }

    @Test func testBranchingTopLevelInitializersGetDistinctLabels() throws {
        let source = """
        val a = if (1 > 2) 1 else 2
        val b = if (1 < 2) 3 else 4

        fun main() {
            println(a)
            println(b)
        }
        """

        let labels = try mainLabelIDs(in: source)
        #expect(labels.count == Set(labels).count,
                "top-level `if` initializers must not reuse each other's labels: \(labels)")
    }

    @Test func testTopLevelInitializerLabelsDoNotCollideWithMainBody() throws {
        let source = """
        val a = if (1 > 2) 1 else 2
        var b = when {
            a > 1 -> 10
            else -> 20
        }

        fun main() {
            if (a > 1) {
                b = b + 1
            } else {
                b = b - 1
            }
            for (i in 0 until 3) {
                b = b + i
            }
            println(b)
        }
        """

        let labels = try mainLabelIDs(in: source)
        #expect(labels.count == Set(labels).count,
                "injected initializer labels must not alias `main`'s own labels: \(labels)")
    }
}
#endif
