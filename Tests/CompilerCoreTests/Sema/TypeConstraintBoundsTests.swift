@testable import CompilerCore
import Testing

private struct MissingFunctionDeclaration: Error, CustomStringConvertible {
    let name: String

    var description: String {
        "Missing function declaration: \(name)"
    }
}

@Suite
struct TypeConstraintBoundsTests {
    @Test func whereClauseAndMultipleUpperBoundsArePreservedInAST() throws {
        let source = """
        class Animal

        fun <T : Comparable<T>> clamp(value: T, min: T, max: T): T = when {
            value < min -> min
            value > max -> max
            else -> value
        }

        fun <T> maxItem(a: T, b: T): T where T : Comparable<T> = if (a > b) a else b

        fun <T> processItem(v: T): String where T : Comparable<T>, T : Any = v.toString()
        """

        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try requireTestValue(ctx.ast, "Missing AST")
        let file = try requireTestValue(ast.files.first, "Missing file")

        func function(named targetName: String) throws -> FunDecl {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(fun) = decl,
                      ctx.interner.resolve(fun.name) == targetName
                else {
                    continue
                }
                return fun
            }
            throw MissingFunctionDeclaration(name: targetName)
        }

        let clamp = try function(named: "clamp")
        #expect(clamp.typeParams.first?.upperBounds.count == 1)

        let maxItem = try function(named: "maxItem")
        #expect(maxItem.typeParams.first?.upperBounds.count == 1)

        let processItem = try function(named: "processItem")
        #expect(processItem.typeParams.first?.upperBounds.count == 2)
    }

    @Test func upperBoundViolationEmitsBoundDiagnostic() {
        let source = """
        class Plain

        fun <T : Comparable<T>> maxItem(a: T, b: T): T = if (a > b) a else b

        fun usePlain(): Plain = maxItem(Plain(), Plain())
        """

        let ctx = runSemaCollectingDiagnostics(source)
        assertHasDiagnostic("KSWIFTK-SEMA-BOUND", in: ctx)
    }

    // KNOWN GAP (DEBT-SEMA-002, migrated from Scripts/diff_cases/error_type_inference.kt / DEBT-DIFF-006):
    // `where T : Int, T : String` combines two mutually exclusive class bounds. kotlinc 2.4.0 rejects the
    // declaration itself:
    //   error: upper bounds of 'T' have an empty intersection.
    //   error: type parameter 'T' ... has inconsistent bounds: Int, String.
    //   error: only one of the upper bounds can be a class.
    // kswiftc only validates bound satisfaction at call sites (see upperBoundViolationEmitsBoundDiagnostic
    // above) and does not yet check bound consistency at the declaration site. This pins the current
    // (incorrect) silent acceptance so it fails once DEBT-SEMA-002 is fixed.
    @Test func conflictingClassUpperBoundsAreNotYetDetected() {
        let source = """
        fun <T> conflicting(a: T, b: T): T where T : Int, T : String = a
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Got: \(ctx.diagnostics.diagnostics)")
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Diagnostic assertions below validate the failure mode.
        }
        return ctx
    }
}
