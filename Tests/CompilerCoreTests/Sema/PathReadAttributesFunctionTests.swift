#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-PATH-FN-030: Validates that the `readAttributes` extension functions
/// on `kotlin.io.path.Path` are wired through Sema for both overloads:
/// - `Path.readAttributes(attributes: String, vararg options: LinkOption): Map<String, Any?>`
///   resolves to `kk_path_readAttributes_string`.
/// - `Path.readAttributes<A : BasicFileAttributes>(vararg options: LinkOption): A`
///   resolves to `kk_path_readAttributes`.
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

    @Test func testPathReadAttributes() throws {
        let source = """
        import java.nio.file.LinkOption
        import java.nio.file.attribute.BasicFileAttributes
        import kotlin.io.path.Path
        import kotlin.io.path.readAttributes

        fun stringAttributes(path: Path, option: LinkOption): Map<String, Any?> {
            val first: Map<String, Any?> = path.readAttributes("basic:*")
            val second: Map<String, Any?> = path.readAttributes("basic:*", option)
            return second
        }

        fun genericAttributes(path: Path, option: LinkOption): BasicFileAttributes {
            val first: BasicFileAttributes = path.readAttributes<BasicFileAttributes>()
            val second: BasicFileAttributes = path.readAttributes<BasicFileAttributes>(option)
            return second
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
        #expect(
            !ctx.diagnostics.hasError,
            "Path.readAttributes extension functions in kotlin.io.path should resolve: \(diagnostics)"
        )

        let interner = ctx.interner
        let sema = try #require(ctx.sema)
        let symbols = sema.symbols
        let types = sema.types
        let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
        let mapSymbol = try #require(symbols.lookup(fqName: ["kotlin", "collections", "Map"].map(interner.intern)))
        let linkOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
        let basicFileAttributesSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "BasicFileAttributes"].map(interner.intern)))
        let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
        let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
        let mapOfStringToNullableAnyType = types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.invariant(types.stringType), .out(types.nullableAnyType)],
            nullability: .nonNull
        )))
        let basicFileAttributesType = types.make(.classType(ClassType(classSymbol: basicFileAttributesSymbol, args: [], nullability: .nonNull)))

        let readAttributesSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "readAttributes"].map(interner.intern))

        let stringOverload = try #require(readAttributesSymbols.first { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == pathType
                && signature.parameterTypes == [types.stringType, linkOptionType]
                && signature.returnType == mapOfStringToNullableAnyType
        })
        #expect(symbols.externalLinkName(for: stringOverload) == "kk_path_readAttributes_string")

        let stringSignature = try #require(symbols.functionSignature(for: stringOverload))
        #expect(stringSignature.valueParameterHasDefaultValues == [false, false])
        #expect(stringSignature.valueParameterIsVararg == [false, true])

        let genericOverload = try #require(readAttributesSymbols.first { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID),
                  let typeParameterSymbol = signature.typeParameterSymbols.first
            else {
                return false
            }
            let returnType = types.make(.typeParam(TypeParamType(
                symbol: typeParameterSymbol,
                nullability: .nonNull
            )))
            return signature.receiverType == pathType
                && signature.parameterTypes == [linkOptionType]
                && signature.returnType == returnType
        })
        #expect(symbols.externalLinkName(for: genericOverload) == "kk_path_readAttributes")

        let genericSignature = try #require(symbols.functionSignature(for: genericOverload))
        #expect(genericSignature.valueParameterHasDefaultValues == [false])
        #expect(genericSignature.valueParameterIsVararg == [true])
        #expect(genericSignature.typeParameterSymbols.count == 1)
        #expect(genericSignature.reifiedTypeParameterIndices == [0])
        #expect(genericSignature.typeParameterUpperBoundsList == [[basicFileAttributesType]])
        let typeParameterSymbol = try #require(genericSignature.typeParameterSymbols.first)
        #expect(symbols.symbol(typeParameterSymbol)?.flags.contains(.reifiedTypeParameter) == true)
        #expect(symbols.typeParameterUpperBounds(for: typeParameterSymbol) == [basicFileAttributesType])

        let ast = try #require(ctx.ast)
        let stringCallExprs = memberCallExprIDs(named: "readAttributes", in: ast, interner: interner)
            .filter { sema.bindings.callBinding(for: $0)?.chosenCallee == stringOverload }
        let genericCallExprs = memberCallExprIDs(named: "readAttributes", in: ast, interner: interner)
            .filter { sema.bindings.callBinding(for: $0)?.chosenCallee == genericOverload }

        #expect(stringCallExprs.count == 2)
        #expect(genericCallExprs.count == 2)
        for callExpr in stringCallExprs {
            #expect(sema.bindings.exprTypes[callExpr] == mapOfStringToNullableAnyType)
        }
        for callExpr in genericCallExprs {
            #expect(sema.bindings.exprTypes[callExpr] == basicFileAttributesType)
        }
    }
}
#endif
