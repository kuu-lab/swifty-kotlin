#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ElvisLhsCallExpectedTypeInferenceTests {
    @Test
    func genericCallOnElvisLeftUsesEnclosingExpectedType() throws {
        let sources = [
            """
            package elvisLhsGenericCall
            interface Node {
                fun <T : Node> child(code: Int): T? = null
            }
            class Branch : Node {
                fun parent(): Node = child(42) ?: this
                fun explicitParent(): Node = child<Node>(42) ?: this
                fun directParent(): Node? = child(42)
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            for path in paths {
                let diagnostics = diagnosticsForPath(path, in: ctx)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: diagnostics)
            }
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "got: \(errors.map { "\($0.code): \($0.message)" })")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let childCalls = allExprIDs(in: ast, path: paths[0], ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "child"
            }
            #expect(childCalls.count == 3)
            let nodeSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("elvisLhsGenericCall"), ctx.interner.intern("Node"),
            ]))
            let nodeType = sema.types.make(.classType(ClassType(
                classSymbol: nodeSymbol, args: [], nullability: .nonNull
            )))
            let contextualCall = try #require(childCalls.first)
            let binding = try #require(sema.bindings.callBinding(for: contextualCall))
            #expect(binding.substitutedTypeArguments == [nodeType])
        }
    }

    @Test
    func genericCallWithoutExpectedTypeStillRejectsUnresolvedTypeArgument() throws {
        let source = """
            package elvisLhsUnresolved
            interface Node {
                fun <T : Node> child(code: Int): T? = null
            }
            fun unresolved(node: Node) = node.child(42)
            """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-INFER", in: diagnosticsForPath(path, in: ctx))
        }
    }
}
#endif
