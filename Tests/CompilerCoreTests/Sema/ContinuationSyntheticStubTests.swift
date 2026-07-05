#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ContinuationSyntheticStubTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test
    func testContinuationAndCoroutineContextStubsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let continuationFQName = ["kotlin", "coroutines", "Continuation"].map { interner.intern($0) }
        let continuationSymbol = try #require(
            sema.symbols.lookup(fqName: continuationFQName),
            "Expected kotlin.coroutines.Continuation to be registered"
        )
        #expect(sema.symbols.symbol(continuationSymbol)?.kind == .interface)
        #expect(sema.symbols.symbol(continuationSymbol)?.flags.contains(.synthetic) == true)

        let continuationTypeParameterSymbols = sema.types.nominalTypeParameterSymbols(for: continuationSymbol)
        #expect(continuationTypeParameterSymbols.count == 1)
        #expect(sema.types.nominalTypeParameterVariances(for: continuationSymbol) == [.invariant])

        let continuationTParamSymbol = try #require(continuationTypeParameterSymbols.first)
        let continuationTType = sema.types.make(.typeParam(TypeParamType(
            symbol: continuationTParamSymbol,
            nullability: .nonNull
        )))
        let continuationType = sema.types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: [.invariant(continuationTType)],
            nullability: .nonNull
        )))

        let coroutineContextFQName = ["kotlin", "coroutines", "CoroutineContext"].map { interner.intern($0) }
        let coroutineContextSymbol = try #require(
            sema.symbols.lookup(fqName: coroutineContextFQName),
            "Expected kotlin.coroutines.CoroutineContext to be registered"
        )
        #expect(sema.symbols.symbol(coroutineContextSymbol)?.kind == .interface)
        #expect(sema.symbols.symbol(coroutineContextSymbol)?.flags.contains(.synthetic) == true)
        let coroutineContextType = sema.types.make(.classType(ClassType(
            classSymbol: coroutineContextSymbol,
            args: [],
            nullability: .nonNull
        )))

        let resultFQName = ["kotlin", "Result"].map { interner.intern($0) }
        let resultSymbol = try #require(
            sema.symbols.lookup(fqName: resultFQName),
            "Expected kotlin.Result to be registered"
        )
        let resultOfContinuationTType = sema.types.make(.classType(ClassType(
            classSymbol: resultSymbol,
            args: [.invariant(continuationTType)],
            nullability: .nonNull
        )))

        let contextSymbol = try #require(
            sema.symbols.lookup(fqName: continuationFQName + [interner.intern("context")]),
            "Expected Continuation.context to be registered"
        )
        #expect(sema.symbols.symbol(contextSymbol)?.kind == .property)
        #expect(sema.symbols.propertyType(for: contextSymbol) == coroutineContextType)

        let resumeWithSymbol = try #require(
            sema.symbols.lookup(fqName: continuationFQName + [interner.intern("resumeWith")]),
            "Expected Continuation.resumeWith to be registered"
        )
        let resumeWithSignature = try #require(sema.symbols.functionSignature(for: resumeWithSymbol))
        #expect(resumeWithSignature.receiverType == continuationType)
        #expect(resumeWithSignature.parameterTypes == [resultOfContinuationTType])
        #expect(resumeWithSignature.returnType == sema.types.unitType)
        #expect(resumeWithSignature.typeParameterSymbols == [continuationTParamSymbol])
        #expect(resumeWithSignature.classTypeParameterCount == 1)

        // Sanity-check the Result<T> shape used by the parameter type.
        #expect(
            resultOfContinuationTType ==
            sema.types.make(.classType(ClassType(
                classSymbol: resultSymbol,
                args: [.invariant(continuationTType)],
                nullability: .nonNull
            )))
        )

        let continuationFactorySymbol = try #require(
            sema.symbols.lookupAll(fqName: continuationFQName).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .function
            },
            "Expected kotlin.coroutines.Continuation factory function to be registered"
        )
        let continuationFactorySignature = try #require(sema.symbols.functionSignature(for: continuationFactorySymbol))
        #expect(sema.symbols.externalLinkName(for: continuationFactorySymbol) == "kk_coroutine_continuation_factory")
        #expect(continuationFactorySignature.typeParameterSymbols.count == 1)
        let continuationFactoryTParamSymbol = try #require(continuationFactorySignature.typeParameterSymbols.first)
        let continuationFactoryTType = sema.types.make(.typeParam(TypeParamType(
            symbol: continuationFactoryTParamSymbol,
            nullability: .nonNull
        )))
        let resultOfContinuationFactoryTType = sema.types.make(.classType(ClassType(
            classSymbol: resultSymbol,
            args: [.invariant(continuationFactoryTType)],
            nullability: .nonNull
        )))
        let continuationFactoryResumeWithType = sema.types.make(.functionType(FunctionType(
            params: [resultOfContinuationFactoryTType],
            returnType: sema.types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let continuationFactoryReturnType = sema.types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: [.invariant(continuationFactoryTType)],
            nullability: .nonNull
        )))
        #expect(continuationFactorySignature.parameterTypes == [
            coroutineContextType,
            continuationFactoryResumeWithType,
        ])
        #expect(continuationFactorySignature.returnType == continuationFactoryReturnType)

        let interceptorFQName = ["kotlin", "coroutines", "ContinuationInterceptor"].map { interner.intern($0) }
        let interceptorSymbol = try #require(
            sema.symbols.lookup(fqName: interceptorFQName),
            "Expected kotlin.coroutines.ContinuationInterceptor to be registered"
        )
        #expect(sema.symbols.symbol(interceptorSymbol)?.kind == .interface)
        let dispatcherFQName = ["kotlinx", "coroutines", "CoroutineDispatcher"].map { interner.intern($0) }
        let dispatcherSymbol = try #require(
            sema.symbols.lookup(fqName: dispatcherFQName),
            "Expected kotlinx.coroutines.CoroutineDispatcher to be registered"
        )
        #expect(
            sema.symbols.directSupertypes(for: dispatcherSymbol).contains(interceptorSymbol),
            "CoroutineDispatcher should be a ContinuationInterceptor"
        )

        let interceptedFQName = ["kotlin", "coroutines", "intrinsics", "intercepted"].map { interner.intern($0) }
        let interceptedSymbol = try #require(
            sema.symbols.lookup(fqName: interceptedFQName),
            "Expected kotlin.coroutines.intrinsics.intercepted to be registered"
        )
        let interceptedSignature = try #require(sema.symbols.functionSignature(for: interceptedSymbol))
        #expect(sema.symbols.externalLinkName(for: interceptedSymbol) == "kk_continuation_intercepted")
        #expect(interceptedSignature.receiverType == continuationType)
        #expect(interceptedSignature.returnType == continuationType)
        #expect(interceptedSignature.typeParameterSymbols == [continuationTParamSymbol])
        #expect(interceptedSignature.classTypeParameterCount == 1)

        let interceptContinuationFQName = ["kotlin", "coroutines", "ContinuationInterceptor", "interceptContinuation"].map { interner.intern($0) }
        let interceptContinuationSymbol = try #require(
            sema.symbols.lookup(fqName: interceptContinuationFQName),
            "Expected kotlin.coroutines.ContinuationInterceptor.interceptContinuation to be registered"
        )
        let interceptContinuationSignature = try #require(sema.symbols.functionSignature(for: interceptContinuationSymbol))
        #expect(sema.symbols.externalLinkName(for: interceptContinuationSymbol) == "kk_continuation_interceptor_intercept_continuation")
        let interceptorType = sema.types.make(.classType(ClassType(
            classSymbol: interceptorSymbol,
            args: [],
            nullability: .nonNull
        )))
        #expect(interceptContinuationSignature.receiverType == interceptorType)
        #expect(interceptContinuationSignature.parameterTypes == [continuationType])
        #expect(interceptContinuationSignature.returnType == continuationType)
        #expect(interceptContinuationSignature.typeParameterSymbols == [continuationTParamSymbol])
    }

    @Test
    func testCreateCoroutineUninterceptedOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let createCoroutineFQName = ["kotlin", "coroutines", "intrinsics", "createCoroutineUnintercepted"].map { interner.intern($0) }
        let createCoroutineSymbols = sema.symbols.lookupAll(fqName: createCoroutineFQName)
        #expect(createCoroutineSymbols.count == 2)

        let signatures = createCoroutineSymbols.compactMap { sema.symbols.functionSignature(for: $0) }
        #expect(signatures.count == 2)
        #expect(signatures.allSatisfy { $0.receiverType != nil })
        #expect(signatures.contains(where: { $0.parameterTypes.count == 1 && $0.typeParameterSymbols.count == 1 }))
        #expect(signatures.contains(where: { $0.parameterTypes.count == 2 && $0.typeParameterSymbols.count == 2 }))
    }

    @Test
    func testCreateCoroutineOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let createCoroutineFQName = ["kotlin", "coroutines", "createCoroutine"].map { interner.intern($0) }
        let createCoroutineSymbols = sema.symbols.lookupAll(fqName: createCoroutineFQName)
        #expect(createCoroutineSymbols.count == 2)

        let signatures = createCoroutineSymbols.compactMap { sema.symbols.functionSignature(for: $0) }
        #expect(signatures.count == 2)
        #expect(createCoroutineSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
        #expect(signatures.allSatisfy { $0.receiverType != nil })
        #expect(signatures.contains(where: { $0.parameterTypes.count == 1 && $0.typeParameterSymbols.count == 1 }))
        #expect(signatures.contains(where: { $0.parameterTypes.count == 2 && $0.typeParameterSymbols.count == 2 }))
    }

    @Test
    func testStartCoroutineOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let startCoroutineFQName = ["kotlin", "coroutines", "startCoroutine"].map { interner.intern($0) }
        let startCoroutineSymbols = sema.symbols.lookupAll(fqName: startCoroutineFQName)
        #expect(startCoroutineSymbols.count == 2)

        let signatures = startCoroutineSymbols.compactMap { sema.symbols.functionSignature(for: $0) }
        #expect(signatures.count == 2)
        #expect(startCoroutineSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
        #expect(signatures.allSatisfy { $0.receiverType != nil })
        #expect(signatures.allSatisfy { $0.returnType == sema.types.unitType })
        #expect(signatures.contains(where: { $0.parameterTypes.count == 1 && $0.typeParameterSymbols.count == 1 }))
        #expect(signatures.contains(where: { $0.parameterTypes.count == 2 && $0.typeParameterSymbols.count == 2 }))
    }

    @Test
    func testContinuationInterceptedResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.Continuation
        import kotlin.coroutines.intrinsics.intercepted

        fun probe(c: Continuation<Int>): Continuation<Int> {
            return c.intercepted()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, calleeName, _, _, _) = expr else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "intercepted"
            })
            let chosenCallee = try #require(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected intercepted() to resolve"
            )
            #expect(
                sema.symbols.externalLinkName(for: chosenCallee) ==
                "kk_continuation_intercepted"
            )
        }
    }

    @Test
    func testContinuationFactoryResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.Continuation
        import kotlin.coroutines.CoroutineContext

        fun probe(context: CoroutineContext): Continuation<Int> {
            return Continuation<Int>(context = context, resumeWith = { result: Result<Int> -> println(result) })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "Continuation"
            })
            let chosenCallee = try #require(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected Continuation(context, resumeWith) to resolve"
            )
            #expect(
                sema.symbols.externalLinkName(for: chosenCallee) ==
                "kk_coroutine_continuation_factory"
            )
        }
    }

    @Test
    func testStartCoroutineNoReceiverResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.Continuation
        import kotlin.coroutines.startCoroutine

        fun probe(block: suspend () -> Int, completion: Continuation<Int>) {
            block.startCoroutine(completion)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, calleeName, _, _, _) = expr else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "startCoroutine"
            })
            let chosenCallee = try #require(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected startCoroutine() to resolve"
            )
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            #expect(sema.bindings.exprTypes[callExpr] == sema.types.unitType)
        }
    }

    @Test
    func testCreateCoroutineNoReceiverResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.Continuation
        import kotlin.coroutines.createCoroutine

        fun probe(block: suspend () -> Int, completion: Continuation<Int>): Continuation<Unit> {
            return block.createCoroutine(completion)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, calleeName, _, _, _) = expr else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "createCoroutine"
            })
            let chosenCallee = try #require(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected createCoroutine() to resolve"
            )
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
        }
    }

    @Test
    func testStartCoroutineWithReceiverResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.Continuation
        import kotlin.coroutines.startCoroutine

        fun probe(block: suspend String.() -> Int, completion: Continuation<Int>) {
            block.startCoroutine("swift", completion)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, calleeName, _, _, _) = expr else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "startCoroutine"
            })
            let chosenCallee = try #require(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected receiver startCoroutine() to resolve"
            )
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            #expect(sema.bindings.exprTypes[callExpr] == sema.types.unitType)
        }
    }
}
#endif
