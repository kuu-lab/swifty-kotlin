#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendGenericExtensionPropertyReifiedTokenTests {
    @Test
    func propertyGetterForwardsBothReifiedTokensIntoItsLambda() throws {
        let source = """
        inline val <reified T> T.kind: (Any) -> Boolean get() = { it is T }
        inline fun <reified U> readKind(value: U): Boolean = value.kind(1)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "GenericExtensionPropertyReifiedTokens",
                emit: .kirDump,
                allowDefaultStdlibLibrary: false
            )
            try runToLowering(ctx)
            let module = try #require(ctx.kir)
            let sema = try #require(ctx.sema)
            let sourceFile = try #require(ctx.sourceManager.fileID(forPath: path))
            let property = try #require(sema.symbols.allSymbols().first { symbol in
                symbol.kind == .property
                    && ctx.interner.resolve(symbol.name) == "kind"
                    && symbol.declSite?.start.file == sourceFile
            })
            let getterSymbol = try #require(sema.symbols.extensionPropertyGetterAccessor(for: property.id))
            let functions = findAllKIRFunctions(in: module)
            let getter = try #require(functions.first { $0.symbol == getterSymbol })
            #expect(getter.params.count == 3)

            let lambdaSymbol = try #require(getter.body.compactMap { instruction -> SymbolID? in
                guard case let .constValue(_, .symbolRef(symbol)) = instruction,
                      let function = functions.first(where: { $0.symbol == symbol }),
                      ctx.interner.resolve(function.name).hasPrefix("kk_lambda_")
                else { return nil }
                return symbol
            }.first)
            let lambda = try #require(functions.first { $0.symbol == lambdaSymbol })
            let callees = extractCallees(from: lambda.body, interner: ctx.interner)
            #expect(callees.contains("kk_op_is"))
            #expect(callees.contains("__kk_pair_first"))
            #expect(callees.contains("__kk_pair_second"))

            let caller = try #require(functions.first { ctx.interner.resolve($0.name) == "readKind" })
            #expect(caller.params.count == 3)
            #expect(extractCallees(from: caller.body, interner: ctx.interner).contains("__kk_pair_new"))
        }
    }
}
#endif
