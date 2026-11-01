#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-3138: an explicit type on a for-loop variable must accept the
/// iterator element type; kotlinc reports an initializer type mismatch.
@Suite
struct ForLoopVariableTypeAnnotationTests {
    private func semaContext(for source: String) throws -> CompilationContext {
        let ctx = makeContextFromSource(source, allowDefaultStdlibLibrary: false)
        try runSema(ctx)
        return ctx
    }

    @Test(arguments: [
        "fun main() { for (c: Int in \"abc\") println(c) }",
        "fun main() { for (c: Double in \"abc\") println(c) }",
        "fun main() { for (x: String in listOf(1, 2)) println(x) }",
        "fun main() { for (c: CharSequence in \"abc\") println(c) }",
    ])
    func mismatchedLoopVariableTypeIsRejected(_ source: String) throws {
        let ctx = try semaContext(for: source)
        assertHasDiagnostic("KSWIFTK-SEMA-0468", in: ctx)
    }

    @Test(arguments: [
        "fun main() { for (c: Char in \"abc\") println(c) }",
        "fun main() { for (c: Any in \"abc\") println(c) }",
        "fun main() { for (c in \"abc\") println(c) }",
        "fun main() { for (x: Number in listOf(1, 2)) println(x) }",
        "fun main() { for (i: Int in 1..3) println(i) }",
    ])
    func matchingOrSupertypeLoopVariableTypeIsAccepted(_ source: String) throws {
        let ctx = try semaContext(for: source)
        assertNoDiagnostic("KSWIFTK-SEMA-0468", in: ctx)
    }

    @Test
    func annotationBeforeLoopVariablePreservesBindingAndAnnotation() throws {
        let ctx = try semaContext(for: #"""
        fun main() {
            for (@Suppress("p") i in 1..3) {
                i
            }
        }
        """#)
        let ast = try #require(ctx.ast)
        let loopIndex = try #require(ast.arena.exprs.indices.first { index in
            if case .forExpr = ast.arena.exprs[index] { return true }
            return false
        })
        let loopID = ExprID(rawValue: Int32(loopIndex))
        guard case let .forExpr(loopVariable, _, _, _, _) = ast.arena.expr(loopID) else {
            Issue.record("Expected a for-loop expression")
            return
        }
        #expect(loopVariable.map { ctx.interner.resolve($0) } == "i")
        #expect(ast.arena.expressionAnnotations(for: loopID).map(\.name) == ["Suppress"])
        #expect(ast.arena.expressionAnnotations(for: loopID).first?.arguments == [#""p""#])

        let bodyReferenceIndex = try #require(ast.arena.exprs.indices.first { index in
            guard case let .nameRef(name, _) = ast.arena.exprs[index] else { return false }
            return ctx.interner.resolve(name) == "i"
        })
        let sema = try #require(ctx.sema)
        #expect(sema.bindings.identifierSymbol(for: ExprID(rawValue: Int32(bodyReferenceIndex))) != nil)
        #expect(!ctx.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0013" && $0.message.contains("Unresolved local variable 'i'")
        })
    }
}
#endif
