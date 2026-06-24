@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ThreadLocalSyntheticStubTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test
    func testThreadLocalConstructorAndGetOrSetSignatures() throws {
        let (sema, interner) = try makeSema()

        let threadLocalFQName = ["java", "lang", "ThreadLocal"].map { interner.intern($0) }
        let threadLocalSymbol = try #require(
            sema.symbols.lookup(fqName: threadLocalFQName),
            "Expected java.lang.ThreadLocal to be registered"
        )
        #expect(sema.symbols.symbol(threadLocalSymbol)?.kind == .class)

        let classTypeParameterSymbols = sema.types.nominalTypeParameterSymbols(for: threadLocalSymbol)
        #expect(classTypeParameterSymbols.count == 1)
        #expect(sema.types.nominalTypeParameterVariances(for: threadLocalSymbol) == [.invariant])

        let classTParamSymbol = try #require(classTypeParameterSymbols.first)
        let classTType = sema.types.make(.typeParam(TypeParamType(
            symbol: classTParamSymbol,
            nullability: .nonNull
        )))
        let threadLocalClassType = sema.types.make(.classType(ClassType(
            classSymbol: threadLocalSymbol,
            args: [.invariant(classTType)],
            nullability: .nonNull
        )))

        let initSymbol = try #require(
            sema.symbols.lookup(fqName: threadLocalFQName + [interner.intern("<init>")]),
            "Expected java.lang.ThreadLocal.<init> to be registered"
        )
        let initSignature = try #require(sema.symbols.functionSignature(for: initSymbol))
        #expect(initSignature.receiverType == nil)
        #expect(initSignature.parameterTypes == [])
        #expect(initSignature.returnType == threadLocalClassType)
        #expect(initSignature.typeParameterSymbols == [classTParamSymbol])
        #expect(initSignature.classTypeParameterCount == 1)
        #expect(sema.symbols.externalLinkName(for: initSymbol) == "kk_thread_local_new")

        let getOrSetFQName = ["kotlin", "concurrent", "getOrSet"].map { interner.intern($0) }
        let getOrSetSymbol = try #require(
            sema.symbols.lookup(fqName: getOrSetFQName),
            "Expected kotlin.concurrent.getOrSet to be registered"
        )
        let getOrSetSignature = try #require(sema.symbols.functionSignature(for: getOrSetSymbol))
        #expect(sema.symbols.symbol(getOrSetSymbol)?.flags.contains(.synthetic) == true)
        #expect(sema.symbols.symbol(getOrSetSymbol)?.flags.contains(.inlineFunction) == true)
        #expect(sema.symbols.externalLinkName(for: getOrSetSymbol) == "kk_thread_local_getOrSet")

        let functionTParamSymbol = try #require(getOrSetSignature.typeParameterSymbols.first)
        #expect(functionTParamSymbol != classTParamSymbol)

        let functionTType = sema.types.make(.typeParam(TypeParamType(
            symbol: functionTParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: threadLocalSymbol,
            args: [.invariant(functionTType)],
            nullability: .nonNull
        )))
        let defaultFunctionType = sema.types.make(.functionType(FunctionType(
            params: [],
            returnType: functionTType
        )))

        #expect(getOrSetSignature.receiverType == receiverType)
        #expect(getOrSetSignature.parameterTypes == [defaultFunctionType])
        #expect(getOrSetSignature.returnType == functionTType)
        #expect(getOrSetSignature.typeParameterSymbols == [functionTParamSymbol])
        #expect(getOrSetSignature.classTypeParameterCount == 0)
    }

    @Test
    func testThreadLocalGetOrSetResolvesInSource() throws {
        let source = """
        import java.lang.ThreadLocal
        import kotlin.concurrent.getOrSet

        fun probe(): Int {
            val tl = ThreadLocal<Int>()
            return tl.getOrSet { 42 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let constructorCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "ThreadLocal"
            })
            let constructorCallee = try #require(
                sema.bindings.callBinding(for: constructorCall)?.chosenCallee
            )
            #expect(
                sema.symbols.externalLinkName(for: constructorCallee) == "kk_thread_local_new"
            )

            let getOrSetCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "getOrSet"
            })
            let chosenGetOrSet = try #require(
                sema.bindings.callBinding(for: getOrSetCall)?.chosenCallee
            )
            #expect(
                sema.symbols.externalLinkName(for: chosenGetOrSet) == "kk_thread_local_getOrSet"
            )
        }
    }
}
