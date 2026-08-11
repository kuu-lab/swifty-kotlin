#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-PATH-FN-030: Validates that the `readAttributes` extension function
/// on `kotlin.io.path.Path` is wired through Sema:
/// - `Path.readAttributes(attributes: String, vararg options: LinkOption): Map<String, Any?>`
///   resolves to `kk_path_readAttributes_string`.
@Suite
struct PathReadAttributesFunctionTests {
    private func memberCallExprIDs(named name: String, in ast: ASTModule, interner: StringInterner) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == name
            else {
                return nil
            }
            return exprID
        }
    }

    @Test func testPathReadAttributesStringOverloadResolvesToRuntimeEntry() throws {
        let source = """
        import java.nio.file.LinkOption
        import kotlin.io.path.Path
        import kotlin.io.path.readAttributes

        fun attributes(path: Path, option: LinkOption): Map<String, Any?> {
            val first: Map<String, Any?> = path.readAttributes("basic:*")
            val second: Map<String, Any?> = path.readAttributes("basic:*", option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(
                !ctx.diagnostics.hasError,
                "Path.readAttributes(attributes, options) extension function in kotlin.io.path should resolve: \(diagnostics)"
            )

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let mapSymbol = try #require(symbols.lookup(fqName: ["kotlin", "collections", "Map"].map(interner.intern)))
            let linkOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let mapOfStringToNullableAnyType = types.make(.classType(ClassType(
                classSymbol: mapSymbol,
                args: [.invariant(types.stringType), .out(types.nullableAnyType)],
                nullability: .nonNull
            )))
            let readAttributesSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "readAttributes"].map(interner.intern))
            let readAttributes = try #require(readAttributesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [types.stringType, linkOptionType]
                    && signature.returnType == mapOfStringToNullableAnyType
            })
            #expect(symbols.externalLinkName(for: readAttributes) == "kk_path_readAttributes_string")

            let signature = try #require(symbols.functionSignature(for: readAttributes))
            #expect(signature.valueParameterHasDefaultValues == [false, false])
            #expect(signature.valueParameterIsVararg == [false, true])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "readAttributes", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == readAttributes)
                #expect(sema.bindings.exprTypes[callExpr] == mapOfStringToNullableAnyType)
            }
        }
    }
}
#endif
