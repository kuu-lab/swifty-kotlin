#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct JvmArrayIsArrayOfSyntheticStubTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testIsArrayOfSignature() throws {
        let (sema, interner) = try makeSema()

        let arrayFQName = ["kotlin", "Array"].map { interner.intern($0) }
        let arraySymbol = try #require(
            sema.symbols.lookup(fqName: arrayFQName),
            "Expected kotlin.Array to be registered"
        )

        let isArrayOfFQName = ["kotlin", "jvm", "isArrayOf"].map { interner.intern($0) }
        let isArrayOfSymbol = try #require(
            sema.symbols.lookup(fqName: isArrayOfFQName),
            "Expected kotlin.jvm.isArrayOf to be registered"
        )
        let isArrayOfSignature = try #require(sema.symbols.functionSignature(for: isArrayOfSymbol))
        #expect(sema.symbols.symbol(isArrayOfSymbol)?.flags.contains(.synthetic) == true)
        #expect(sema.symbols.symbol(isArrayOfSymbol)?.flags.contains(.inlineFunction) == true)
        #expect(sema.symbols.externalLinkName(for: isArrayOfSymbol) == "kk_array_isArrayOf")

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.star],
            nullability: .nonNull
        )))

        #expect(isArrayOfSignature.receiverType == receiverType)
        #expect(isArrayOfSignature.parameterTypes == [])
        #expect(isArrayOfSignature.returnType == sema.types.booleanType)
        #expect(isArrayOfSignature.typeParameterSymbols.count == 1)
        #expect(isArrayOfSignature.reifiedTypeParameterIndices == [0])
        #expect(isArrayOfSignature.typeParameterUpperBoundsList == [[sema.types.anyType]])
        #expect(isArrayOfSignature.classTypeParameterCount == 0)

        let typeParameterSymbol = try #require(isArrayOfSignature.typeParameterSymbols.first)
        #expect(sema.symbols.symbol(typeParameterSymbol)?.flags.contains(.reifiedTypeParameter) == true)
        #expect(sema.symbols.typeParameterUpperBounds(for: typeParameterSymbol) == [sema.types.anyType])
    }

    @Test func testIsArrayOfResolvesInSource() throws {
        let source = """
        import kotlin.jvm.isArrayOf

        fun probe(values: Array<*>): Boolean {
            return values.isArrayOf<String>()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let isArrayOfCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "isArrayOf"
            })
            let chosenIsArrayOf = try #require(
                sema.bindings.callBinding(for: isArrayOfCall)?.chosenCallee
            )
            #expect(
                sema.symbols.externalLinkName(for: chosenIsArrayOf) == "kk_array_isArrayOf"
            )
        }
    }
}
#endif
