#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CoroutineSyntheticStubTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test
    func testEmptyCoroutineContextIsRegisteredAsSyntheticObject() throws {
        let (sema, interner) = try makeSema()

        let coroutineContextFQName = ["kotlin", "coroutines", "CoroutineContext"].map { interner.intern($0) }
        let coroutineContextSymbol = try #require(
            sema.symbols.lookup(fqName: coroutineContextFQName),
            "Expected kotlin.coroutines.CoroutineContext to be registered"
        )
        #expect(sema.symbols.symbol(coroutineContextSymbol)?.kind == .interface)

        let emptyCoroutineContextFQName = ["kotlin", "coroutines", "EmptyCoroutineContext"].map { interner.intern($0) }
        let emptyCoroutineContextSymbol = try #require(
            sema.symbols.lookup(fqName: emptyCoroutineContextFQName),
            "Expected kotlin.coroutines.EmptyCoroutineContext to be registered"
        )
        let emptyCoroutineContextInfo = try #require(sema.symbols.symbol(emptyCoroutineContextSymbol))
        #expect(emptyCoroutineContextInfo.kind == .object)
        #expect(emptyCoroutineContextInfo.flags.contains(.synthetic))

        let expectedEmptyCoroutineContextType = sema.types.make(.classType(ClassType(
            classSymbol: emptyCoroutineContextSymbol,
            args: [],
            nullability: .nonNull
        )))
        #expect(
            sema.symbols.propertyType(for: emptyCoroutineContextSymbol) ==
            expectedEmptyCoroutineContextType
        )
        #expect(
            sema.symbols.directSupertypes(for: emptyCoroutineContextSymbol) ==
            [coroutineContextSymbol]
        )
    }

    @Test
    func testEmptyCoroutineContextResolvesThroughWithContext() throws {
        let source = """
        import kotlin.coroutines.EmptyCoroutineContext
        import kotlinx.coroutines.withContext

        suspend fun probe() {
            withContext(EmptyCoroutineContext) { 42 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty)
        }
    }

    @Test
    func testCoroutineSuspendedTopLevelValIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = [
            "kotlin",
            "coroutines",
            "intrinsics",
            "COROUTINE_SUSPENDED",
        ].map { interner.intern($0) }

        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED to be registered"
        )
        let semanticSymbol = try #require(sema.symbols.symbol(symbol))
        #expect(semanticSymbol.kind == .property)
        #expect(semanticSymbol.visibility == .public)
        #expect(semanticSymbol.flags.contains(.synthetic))
        #expect(sema.symbols.propertyType(for: symbol) == sema.types.nullableAnyType)
        #expect(
            sema.symbols.externalLinkName(for: symbol) ==
            "kk_coroutine_suspended"
        )
    }

    @Test
    func testCoroutineContextTopLevelPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "coroutines", "coroutineContext"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.coroutines.coroutineContext to be registered"
        )
        let info = try #require(sema.symbols.symbol(symbol))
        #expect(info.kind == .property)
        #expect(info.visibility == .public)
        #expect(info.flags.contains(.synthetic))
        #expect(sema.symbols.externalLinkName(for: symbol) == "kk_coroutine_current_context")

        let coroutineContextSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "coroutines", "CoroutineContext"].map { interner.intern($0) })
        )
        guard case let .classType(propertyType) = sema.types.kind(of: try #require(sema.symbols.propertyType(for: symbol))) else {
            Issue.record("Expected coroutineContext property type to be CoroutineContext"); return
        }
        #expect(propertyType.classSymbol == coroutineContextSymbol)
        #expect(propertyType.args.isEmpty)
    }

    @Test
    func testCoroutineContextTopLevelPropertyResolvesInSuspendSource() throws {
        let source = """
        import kotlin.coroutines.CoroutineContext
        import kotlin.coroutines.coroutineContext

        suspend fun probe(): CoroutineContext {
            return coroutineContext
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty)
        }
    }

    @Test
    func testSuspendCoroutineUninterceptedOrReturnStubIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "coroutines", "intrinsics", "suspendCoroutineUninterceptedOrReturn"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fqName))
        let info = try #require(sema.symbols.symbol(symbol))
        #expect(info.kind == .function)
        #expect(info.flags.contains(.synthetic))
        #expect(info.flags.contains(.inlineFunction))
        #expect(info.flags.contains(.suspendFunction))

        let signature = try #require(sema.symbols.functionSignature(for: symbol))
        #expect(signature.isSuspend)
        #expect(signature.typeParameterSymbols.count == 1)
        #expect(signature.parameterTypes.count == 1)

        let continuationFQName = ["kotlin", "coroutines", "Continuation"].map { interner.intern($0) }
        let continuationSymbol = try #require(sema.symbols.lookup(fqName: continuationFQName))
        #expect(sema.types.nominalTypeParameterSymbols(for: continuationSymbol).count == 1)
        let typeParamSymbol = try #require(signature.typeParameterSymbols.first)
        let typeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let continuationType = sema.types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        let expectedBlockType = sema.types.make(.functionType(FunctionType(
            params: [continuationType],
            returnType: sema.types.nullableAnyType,
            isSuspend: false,
            nullability: .nonNull
        )))

        #expect(signature.parameterTypes.first == expectedBlockType)
        #expect(signature.returnType == typeParamType)
    }

    @Test
    func testSuspendCoroutineAndContinuationSignatures() throws {
        let (sema, interner) = try makeSema()

        let continuationFQName = ["kotlin", "coroutines", "Continuation"].map { interner.intern($0) }
        let continuationSymbol = try #require(
            sema.symbols.lookup(fqName: continuationFQName),
            "Expected kotlin.coroutines.Continuation to be registered"
        )
        #expect(sema.symbols.symbol(continuationSymbol)?.kind == .interface)

        let continuationTypeParams = sema.types.nominalTypeParameterSymbols(for: continuationSymbol)
        #expect(continuationTypeParams.count == 1)
        #expect(sema.types.nominalTypeParameterVariances(for: continuationSymbol) == [.invariant])

        _ = try #require(sema.symbols.propertyType(for: continuationSymbol))

        let contextSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "coroutines", "Continuation", "context"].map { interner.intern($0) })
        )
        #expect(sema.symbols.externalLinkName(for: contextSymbol) == "kk_coroutine_continuation_context")
        guard case let .classType(contextType) = sema.types.kind(of: try #require(sema.symbols.propertyType(for: contextSymbol))) else {
            Issue.record("Expected continuation.context to be a class type"); return
        }
        #expect(
            try contextType.classSymbol ==
            #require(sema.symbols.lookup(fqName: ["kotlin", "coroutines", "CoroutineContext"].map { interner.intern($0) }))
        )
        #expect(contextType.args.isEmpty)

        let resumeWithFQName = ["kotlin", "coroutines", "Continuation", "resumeWith"].map { interner.intern($0) }
        let resumeWithSymbol = try #require(sema.symbols.lookup(fqName: resumeWithFQName))
        let resumeWithSignature = try #require(sema.symbols.functionSignature(for: resumeWithSymbol))
        #expect(sema.symbols.externalLinkName(for: resumeWithSymbol) == "kk_coroutine_continuation_resume_with")
        guard case let .classType(resumeWithReceiverType) = sema.types.kind(of: try #require(resumeWithSignature.receiverType)) else {
            Issue.record("Expected resumeWith receiver to be Continuation<T>"); return
        }
        #expect(resumeWithReceiverType.classSymbol == continuationSymbol)
        #expect(resumeWithReceiverType.args.count == 1)
        #expect(resumeWithSignature.parameterTypes.count == 1)
        #expect(resumeWithSignature.returnType == sema.types.unitType)
        #expect(resumeWithSignature.classTypeParameterCount == 1)

        let resultSymbol = try #require(sema.symbols.lookup(fqName: ["kotlin", "Result"].map { interner.intern($0) }))
        guard case let .classType(resumeWithParameterType) = sema.types.kind(of: resumeWithSignature.parameterTypes[0]) else {
            Issue.record("Expected resumeWith parameter to be Result<T>"); return
        }
        #expect(resumeWithParameterType.classSymbol == resultSymbol)
        #expect(resumeWithParameterType.args.count == 1)

        let resumeFQName = ["kotlin", "coroutines", "resume"].map { interner.intern($0) }
        let resumeSymbol = try #require(sema.symbols.lookup(fqName: resumeFQName))
        let resumeSignature = try #require(sema.symbols.functionSignature(for: resumeSymbol))
        #expect(sema.symbols.externalLinkName(for: resumeSymbol) == "kk_coroutine_continuation_resume")
        guard case let .classType(resumeReceiverType) = sema.types.kind(of: try #require(resumeSignature.receiverType)) else {
            Issue.record("Expected resume receiver to be Continuation<T>"); return
        }
        #expect(resumeReceiverType.classSymbol == continuationSymbol)
        #expect(resumeReceiverType.args.count == 1)
        let resumeParameterType = try #require(resumeSignature.parameterTypes.first)
        guard case let .typeParam(resumeTypeParam) = sema.types.kind(of: resumeParameterType) else {
            Issue.record("Expected resume parameter to be the continuation type parameter, got \(sema.types.renderType(resumeParameterType))"); return
        }
        #expect(resumeTypeParam.symbol.rawValue != -1)
        #expect(resumeSignature.returnType == sema.types.unitType)
        #expect(resumeSignature.classTypeParameterCount == 1)

        let resumeWithExceptionFQName = ["kotlin", "coroutines", "resumeWithException"].map { interner.intern($0) }
        let resumeWithExceptionSymbol = try #require(sema.symbols.lookup(fqName: resumeWithExceptionFQName))
        let resumeWithExceptionSignature = try #require(sema.symbols.functionSignature(for: resumeWithExceptionSymbol))
        #expect(sema.symbols.externalLinkName(for: resumeWithExceptionSymbol) == "kk_coroutine_continuation_resume_with_exception")
        guard case let .classType(resumeWithExceptionReceiverType) = sema.types.kind(of: try #require(resumeWithExceptionSignature.receiverType)) else {
            Issue.record("Expected resumeWithException receiver to be Continuation<T>"); return
        }
        #expect(resumeWithExceptionReceiverType.classSymbol == continuationSymbol)
        #expect(resumeWithExceptionReceiverType.args.count == 1)
        #expect(resumeWithExceptionSignature.parameterTypes.count == 1)
        #expect(resumeWithExceptionSignature.returnType == sema.types.unitType)
        #expect(resumeWithExceptionSignature.classTypeParameterCount == 1)

        let suspendCoroutineFQName = ["kotlin", "coroutines", "suspendCoroutine"].map { interner.intern($0) }
        let suspendCoroutineSymbol = try #require(sema.symbols.lookup(fqName: suspendCoroutineFQName))
        let suspendCoroutineSignature = try #require(sema.symbols.functionSignature(for: suspendCoroutineSymbol))
        #expect(sema.symbols.symbol(suspendCoroutineSymbol)?.flags.contains(.synthetic) == true)
        #expect(sema.symbols.symbol(suspendCoroutineSymbol)?.flags.contains(.inlineFunction) == true)
        #expect(sema.symbols.externalLinkName(for: suspendCoroutineSymbol) == "kk_suspend_coroutine")
        #expect(suspendCoroutineSignature.isSuspend)
        #expect(suspendCoroutineSignature.typeParameterSymbols.count == 1)
        #expect(suspendCoroutineSignature.returnType == sema.types.make(.typeParam(TypeParamType(
            symbol: suspendCoroutineSignature.typeParameterSymbols[0],
            nullability: .nonNull
        ))))
    }

    @Test
    func testCancellationExceptionClassAndConstructorsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let cancellationFQName = ["kotlin", "coroutines", "cancellation", "CancellationException"].map {
            interner.intern($0)
        }
        let cancellationSymbol = try #require(
            sema.symbols.lookup(fqName: cancellationFQName),
            "Expected kotlin.coroutines.cancellation.CancellationException to be registered"
        )
        #expect(sema.symbols.symbol(cancellationSymbol)?.kind == .class)
        #expect(sema.symbols.symbol(cancellationSymbol)?.flags.contains(.synthetic) == true)

        let exceptionSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "Exception"].map { interner.intern($0) })
        )
        #expect(sema.symbols.directSupertypes(for: cancellationSymbol).contains(exceptionSymbol))

        let throwableSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "Throwable"].map { interner.intern($0) })
        )

        let ctorFQName = cancellationFQName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: ctorFQName)
        #expect(constructors.count == 4)

        let nullableThrowableType = sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nullable
        )))
        let expectedParameterTypes: Set<[TypeID]> = [
            [],
            [sema.types.stringType],
            [nullableThrowableType],
            [sema.types.stringType, nullableThrowableType],
        ]
        let actualParameterTypes = Set(constructors.compactMap { sema.symbols.functionSignature(for: $0)?.parameterTypes })
        #expect(actualParameterTypes == expectedParameterTypes)

        let causeConstructor = try #require(constructors.first { symbol in
            sema.symbols.functionSignature(for: symbol)?.parameterTypes == [sema.types.stringType, nullableThrowableType]
        })
        #expect(sema.symbols.externalLinkName(for: causeConstructor) == "kk_throwable_new_with_cause")
    }

    @Test
    func testSuspendCoroutineIntrinsicCanBeShadowedByUserFunction() throws {
        let source = """
        fun suspendCoroutineUninterceptedOrReturn(block: (Any?) -> Any?): Any? = block(null)

        fun probe(): Any? {
            return suspendCoroutineUninterceptedOrReturn { value -> value }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError))

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "suspendCoroutineUninterceptedOrReturn"
            })

            #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil)
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let chosenInfo = try #require(sema.symbols.symbol(chosenCallee))
            #expect(!(chosenInfo.flags.contains(.synthetic)))
        }
    }

    @Test
    func testSuspendCoroutineIntrinsicResolvesThroughImport() throws {
        let source = """
        import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn

        suspend fun probe(): Any? {
            return suspendCoroutineUninterceptedOrReturn { cont ->
                cont
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let suspendCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "suspendCoroutineUninterceptedOrReturn"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: suspendCall)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
        }
    }

    @Test
    func testSuspendCoroutineResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.*

        suspend fun probe(): Int {
            return suspendCoroutine<Int> { cont: Continuation<Int> ->
                cont.resume(42)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let suspendCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "suspendCoroutine"
            })
            let chosenSuspendCoroutine = try #require(sema.bindings.callBinding(for: suspendCall)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenSuspendCoroutine) == "kk_suspend_coroutine")
        }
    }

    @Test
    func testResumeWithExceptionResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.*

        suspend fun probe(): Int {
            return suspendCoroutine<Int> { cont: Continuation<Int> ->
                cont.resumeWithException(Exception())
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)

            _ = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, calleeName, _, _, _) = expr else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "resumeWithException"
            })
        }
    }

    @Test
    func testContinuationContextResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.*

        suspend fun probe(): Int {
            return suspendCoroutine<Int> { cont: Continuation<Int> ->
                val context = cont.context
                cont.resume(42)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func testResumeWithResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.*

        suspend fun probe(): Int {
            return suspendCoroutine<Int> { cont: Continuation<Int> ->
                cont.resumeWith(runCatching { 42 })
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func testCancellationExceptionCauseConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let cancellationFQName = ["kotlin", "coroutines", "cancellation", "CancellationException"].map {
            interner.intern($0)
        }
        let cancellationSymbol = try #require(sema.symbols.lookup(fqName: cancellationFQName))
        let throwableSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "Throwable"].map { interner.intern($0) })
        )
        let nullableThrowableType = sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nullable
        )))

        let constructors = sema.symbols.lookupAll(fqName: cancellationFQName + [interner.intern("<init>")])
        let causeConstructor = try #require(constructors.first { symbol in
            sema.symbols.functionSignature(for: symbol)?.parameterTypes == [nullableThrowableType]
        })
        let causeSignature = try #require(sema.symbols.functionSignature(for: causeConstructor))
        #expect(causeSignature.returnType == sema.symbols.propertyType(for: cancellationSymbol))
        #expect(sema.symbols.externalLinkName(for: causeConstructor) == "kk_throwable_new_cause")
    }
}
#endif
