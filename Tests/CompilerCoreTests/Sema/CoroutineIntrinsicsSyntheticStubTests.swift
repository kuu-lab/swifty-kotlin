#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CoroutineIntrinsicsSyntheticStubTests {
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
    func testCoroutineIntrinsicsStubsAreRegisteredWithExpectedShapes() throws {
        let (sema, interner) = try makeSema()

        let continuationFQName = ["kotlin", "coroutines", "Continuation"].map { interner.intern($0) }
        let continuationSymbol = try #require(
            sema.symbols.lookup(fqName: continuationFQName),
            "Expected kotlin.coroutines.Continuation to be registered"
        )
        #expect(sema.symbols.symbol(continuationSymbol)?.kind == .interface)
        let continuationTypeParams = sema.types.nominalTypeParameterSymbols(for: continuationSymbol)
        #expect(continuationTypeParams.count == 1)

        let coroutineSuspendedFQName = ["kotlin", "coroutines", "intrinsics", "COROUTINE_SUSPENDED"].map { interner.intern($0) }
        let coroutineSuspendedSymbol = try #require(
            sema.symbols.lookup(fqName: coroutineSuspendedFQName),
            "Expected COROUTINE_SUSPENDED to be registered"
        )
        #expect(sema.symbols.symbol(coroutineSuspendedSymbol)?.kind == .property)
        #expect(sema.symbols.externalLinkName(for: coroutineSuspendedSymbol) == "kk_coroutine_suspended")
        #expect(sema.symbols.propertyType(for: coroutineSuspendedSymbol) == sema.types.nullableAnyType)

        let suspendIntrinsicFQName = ["kotlin", "coroutines", "intrinsics", "suspendCoroutineUninterceptedOrReturn"].map { interner.intern($0) }
        let suspendIntrinsicSymbol = try #require(
            sema.symbols.lookup(fqName: suspendIntrinsicFQName),
            "Expected suspendCoroutineUninterceptedOrReturn to be registered"
        )
        #expect(sema.symbols.symbol(suspendIntrinsicSymbol)?.kind == .function)
        #expect(sema.symbols.externalLinkName(for: suspendIntrinsicSymbol) == nil)

        let signature = try #require(sema.symbols.functionSignature(for: suspendIntrinsicSymbol))
        #expect(signature.isSuspend == true)
        #expect(signature.parameterTypes.count == 1)
        #expect(signature.typeParameterSymbols.count == 1)

        let functionTypeParam = try #require(signature.typeParameterSymbols.first)
        let functionTypeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: functionTypeParam,
            nullability: .nonNull
        )))
        let functionContinuationType = sema.types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: [.invariant(functionTypeParamType)],
            nullability: .nonNull
        )))
        let blockType = sema.types.make(.functionType(FunctionType(
            params: [functionContinuationType],
            returnType: sema.types.nullableAnyType,
            isSuspend: false,
            nullability: .nonNull
        )))

        #expect(signature.parameterTypes == [blockType])
        #expect(signature.returnType == functionTypeParamType)
    }

    @Test
    func testSuspendCoroutineIntrinsicsResolveInSource() throws {
        let source = """
        import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
        import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn

        suspend fun probe(): Int {
            return suspendCoroutineUninterceptedOrReturn { continuation ->
                COROUTINE_SUSPENDED
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

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

            #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == .suspendCoroutineUninterceptedOrReturn)
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(
                sema.symbols.externalLinkName(for: chosenCallee) ==
                nil
            )
            #expect(sema.bindings.exprTypes[callExpr] == sema.types.intType)
        }
    }

    @Test
    func testStartCoroutineUninterceptedOrReturnOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let fqName = ["kotlin", "coroutines", "intrinsics", "startCoroutineUninterceptedOrReturn"].map {
            interner.intern($0)
        }
        let symbols = sema.symbols.lookupAll(fqName: fqName)
        #expect(symbols.count == 2)

        let signatures = symbols.compactMap { sema.symbols.functionSignature(for: $0) }
        #expect(signatures.count == 2)
        #expect(symbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
        #expect(symbols.allSatisfy { sema.symbols.symbol($0)?.flags.contains(.inlineFunction) == true })
        #expect(signatures.allSatisfy { $0.receiverType != nil })
        #expect(signatures.allSatisfy { $0.returnType == sema.types.nullableAnyType })
        #expect(signatures.contains(where: { $0.parameterTypes.count == 1 && $0.typeParameterSymbols.count == 1 }))
        #expect(signatures.contains(where: { $0.parameterTypes.count == 2 && $0.typeParameterSymbols.count == 2 }))
    }

    @Test
    func testRestrictsSuspensionAnnotationIsRegisteredWithClassTarget() throws {
        let (sema, interner) = try makeSema()

        let fqName = ["kotlin", "coroutines", "RestrictsSuspension"].map {
            interner.intern($0)
        }
        let symbolID = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.coroutines.RestrictsSuspension to be registered"
        )
        let symbol = try #require(sema.symbols.symbol(symbolID))
        #expect(symbol.kind == .annotationClass)
        #expect(symbol.visibility == .public)
        #expect(symbol.flags.contains(.synthetic))

        let annotations = sema.symbols.annotations(for: symbolID)
        #expect(
            annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == ["AnnotationTarget.CLASS"]
            },
            "RestrictsSuspension should target class-like declarations, got: \(annotations)"
        )
    }

    @Test
    func testRestrictsSuspensionAnnotationTargetsClassLikeDeclarationsOnly() throws {
        let acceptedSource = """
        import kotlin.coroutines.RestrictsSuspension

        @RestrictsSuspension
        class Scope

        @RestrictsSuspension
        interface ScopeInterface
        """
        let acceptedCtx = makeContextFromSource(acceptedSource)
        try runSema(acceptedCtx)
        let acceptedDiagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: acceptedCtx)
        #expect(
            acceptedDiagnostics.isEmpty,
            "Expected RestrictsSuspension to accept class-like declarations, got: \(acceptedCtx.diagnostics.diagnostics)"
        )

        let rejectedSource = """
        import kotlin.coroutines.RestrictsSuspension

        @RestrictsSuspension
        fun bad() {}
        """
        let rejectedCtx = makeContextFromSource(rejectedSource)
        try runSema(rejectedCtx)
        let rejectedDiagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: rejectedCtx)
        #expect(
            rejectedDiagnostics.count == 1,
            "Expected RestrictsSuspension to reject function declarations, got: \(rejectedCtx.diagnostics.diagnostics)"
        )
        #expect(rejectedDiagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    @Test
    func testStartCoroutineUninterceptedOrReturnResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.Continuation
        import kotlin.coroutines.intrinsics.startCoroutineUninterceptedOrReturn

        fun probe(block: suspend () -> Int, completion: Continuation<Int>): Any? {
            return block.startCoroutineUninterceptedOrReturn(completion)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, memberName, _, _, _) = expr else { return false }
                return ctx.interner.resolve(memberName) == "startCoroutineUninterceptedOrReturn"
            })

            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            #expect(sema.bindings.exprTypes[callExpr] == sema.types.nullableAnyType)
        }
    }

    private func diagnostics(withCode code: String, in ctx: CompilationContext) -> [Diagnostic] {
        ctx.diagnostics.diagnostics.filter { $0.code == code }
    }

    private func isError(_ diagnostic: Diagnostic) -> Bool {
        diagnostic.severity == .error
    }
}
#endif
