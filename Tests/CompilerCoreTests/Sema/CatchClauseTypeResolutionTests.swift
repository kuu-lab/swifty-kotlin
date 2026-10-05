#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// KUU-950: `catch (e: T)` must resolve `T` through the same name-resolution
// path as declarations and `is`/`as` expressions — import priority (explicit >
// wildcard > default), import aliases, and qualified names. Previously the
// catch parameter went through an ad-hoc short-name lookup that ignored
// imports entirely, so `IOException` bound to `java.io.IOException` even when
// the source explicitly imported `kotlinx.io.IOException`.

private nonisolated(unsafe) var _catchTypeResolutionCtx: (ctx: CompilationContext, paths: [String])?

private let qualifiedCatchTypeNames = [
    "kotlin.IllegalStateException",
    "kotlin.UninitializedPropertyAccessException",
    "kotlin.RuntimeException",
    "kotlin.Throwable",
    "java.io.IOException",
    "kotlinx.io.EOFException",
]

private func sharedCatchTypeResolutionCtx() throws -> (ctx: CompilationContext, paths: [String]) {
    if let cached = _catchTypeResolutionCtx { return cached }
    let sources: [String] = [
        """
            package catchres0
            import kotlinx.io.IOException

            fun catchImported(): String {
                return try {
                    "try"
                } catch (e: IOException) {
                    "catch"
                }
            }
        """,
        """
            package catchres1
            import kotlinx.io.*

            fun catchWildcardImported(): String {
                return try {
                    "try"
                } catch (e: IOException) {
                    "catch"
                }
            }
        """,
        """
            package catchres2
            import kotlinx.io.IOException as KxIOException

            fun catchAliased(): String {
                return try {
                    "try"
                } catch (e: KxIOException) {
                    "catch"
                }
            }
        """,
        """
            package catchres3

            fun catchQualified(): String {
                return try {
                    "try"
                } catch (e: kotlinx.io.IOException) {
                    "catch"
                }
            }
        """,
        """
            package catchres4
            import java.io.IOException

            fun catchJavaImported(): String {
                return try {
                    "try"
                } catch (e: IOException) {
                    "catch"
                }
            }
        """,
    ] + qualifiedCatchTypeNames.enumerated().map { index, typeName in
        """
            package catchqualified\(index)

            fun catchQualified(): String {
                return try {
                    "try"
                } catch (e: \(typeName)) {
                    "catch"
                }
            }
        """
    }
    var result: (ctx: CompilationContext, paths: [String])?
    try withTemporaryFiles(contents: sources) { paths in
        let ctx = makeCompilationContext(inputs: paths)
        try runSema(ctx)
        result = (ctx, paths)
    }
    let pair = try #require(result)
    _catchTypeResolutionCtx = pair
    return pair
}

@Suite(.serialized)
struct CatchClauseTypeResolutionTests {
    private func catchParamClassSymbol(
        in ctx: CompilationContext,
        path: String
    ) throws -> SymbolID {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let tryExprID = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
            if case .tryExpr = expr {
                return true
            }
            return false
        })
        guard case let .tryExpr(_, catchClauses, _, _)? = ast.arena.expr(tryExprID),
              let clause = catchClauses.first
        else {
            Issue.record("Expected try expression with a catch clause")
            return .invalid
        }
        let binding = try #require(sema.bindings.catchClauseBinding(for: clause.body))
        guard case let .classType(classType) = sema.types.kind(of: binding.parameterType) else {
            Issue.record("Expected class catch parameter type")
            return .invalid
        }
        return classType.classSymbol
    }

    private func requireClassSymbol(
        _ fqName: [String],
        in ctx: CompilationContext
    ) throws -> SymbolID {
        let sema = try #require(ctx.sema)
        return try #require(
            sema.symbols.lookup(fqName: fqName.map { ctx.interner.intern($0) }),
            "Expected bundled class \(fqName.joined(separator: ".")) to exist"
        )
    }

    @Test func testCatchTypeFollowsExplicitImport() throws {
        let (ctx, paths) = try sharedCatchTypeResolutionCtx()
        #expect(
            try catchParamClassSymbol(in: ctx, path: paths[0]) ==
                requireClassSymbol(["kotlinx", "io", "IOException"], in: ctx)
        )
        assertNoDiagnostic("KSWIFTK-SEMA-0085", in: diagnosticsForPath(paths[0], in: ctx))
    }

    @Test func testCatchTypeFollowsWildcardImport() throws {
        let (ctx, paths) = try sharedCatchTypeResolutionCtx()
        #expect(
            try catchParamClassSymbol(in: ctx, path: paths[1]) ==
                requireClassSymbol(["kotlinx", "io", "IOException"], in: ctx)
        )
        assertNoDiagnostic("KSWIFTK-SEMA-0085", in: diagnosticsForPath(paths[1], in: ctx))
    }

    @Test func testCatchTypeFollowsImportAlias() throws {
        let (ctx, paths) = try sharedCatchTypeResolutionCtx()
        #expect(
            try catchParamClassSymbol(in: ctx, path: paths[2]) ==
                requireClassSymbol(["kotlinx", "io", "IOException"], in: ctx)
        )
        assertNoDiagnostic("KSWIFTK-SEMA-0085", in: diagnosticsForPath(paths[2], in: ctx))
    }

    @Test func testCatchTypeResolvesQualifiedName() throws {
        let (ctx, paths) = try sharedCatchTypeResolutionCtx()
        #expect(
            try catchParamClassSymbol(in: ctx, path: paths[3]) ==
                requireClassSymbol(["kotlinx", "io", "IOException"], in: ctx)
        )
        assertNoDiagnostic("KSWIFTK-SEMA-0085", in: diagnosticsForPath(paths[3], in: ctx))
    }

    @Test func testCatchTypeFollowsJavaIoImport() throws {
        let (ctx, paths) = try sharedCatchTypeResolutionCtx()
        #expect(
            try catchParamClassSymbol(in: ctx, path: paths[4]) ==
                requireClassSymbol(["java", "io", "IOException"], in: ctx)
        )
        assertNoDiagnostic("KSWIFTK-SEMA-0085", in: diagnosticsForPath(paths[4], in: ctx))
    }

    @Test(arguments: qualifiedCatchTypeNames.indices)
    func testPackageQualifiedCatchTypePreservesPathAndClassSymbol(index: Int) throws {
        let (ctx, paths) = try sharedCatchTypeResolutionCtx()
        let path = paths[5 + index]
        let typeName = qualifiedCatchTypeNames[index]
        let expectedPath = typeName.split(separator: ".").map(String.init)
        let ast = try #require(ctx.ast)
        let tryExprID = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
            if case .tryExpr = expr { return true }
            return false
        })
        guard case let .tryExpr(_, clauses, _, _)? = ast.arena.expr(tryExprID),
              let typeRef = clauses.first?.paramType,
              case let .named(parsedPath, _, _)? = ast.arena.typeRef(typeRef)
        else {
            Issue.record("Expected named catch parameter type for \(typeName)")
            return
        }
        #expect(parsedPath.map { ctx.interner.resolve($0) } == expectedPath)
        #expect(try catchParamClassSymbol(in: ctx, path: path) == requireClassSymbol(expectedPath, in: ctx))
        #expect(diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }.isEmpty)
    }

    @Test(arguments: [
        "NonExistentException",
        "kotlin.NonExistentException",
        "missing.IllegalStateException",
        "missing.io.IOException",
    ])
    func testUnresolvedCatchTypeStillEmitsSema0085(typeName: String) throws {
        var diagnosticsByPath: [Diagnostic] = []
        try withTemporaryFiles(contents: [
            """
                package catchresbad
                fun f(): String {
                    return try {
                        "try"
                    } catch (e: \(typeName)) {
                        "catch"
                    }
                }
            """,
        ]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            diagnosticsByPath = diagnosticsForPath(paths[0], in: ctx)
        }
        assertHasDiagnostic("KSWIFTK-SEMA-0085", in: diagnosticsByPath)
        #expect(diagnosticsByPath.contains {
            $0.code == "KSWIFTK-SEMA-0085"
                && $0.message == "Unresolved exception type '\(typeName)' in catch clause."
        })
    }
}
#endif
