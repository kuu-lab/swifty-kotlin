#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testSuspendCoroutineUninterceptedOrReturnLoweringReturnsOnSuspendedToken() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()
        let anyType = fixture.types.anyType

        let continuationSymbol = defineSemanticSymbol(
            in: fixture,
            kind: .interface,
            fqName: ["kotlin", "coroutines", "Continuation"]
        )
        let continuationType = fixture.types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: [.invariant(anyType)],
            nullability: .nonNull
        )))
        let blockType = fixture.types.make(.functionType(FunctionType(
            params: [continuationType],
            returnType: anyType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let suspendedExpr = appendTypedExpr(
            .call(
                callee: appendTypedExpr(
                    .nameRef(fixture.interner.intern("kk_coroutine_suspended"), range),
                    type: anyType,
                    fixture: fixture
                ),
                typeArgs: [],
                args: [],
                range: range
            ),
            type: anyType,
            fixture: fixture
        )
        let lambdaBody = suspendedExpr
        let lambdaExpr = appendTypedExpr(
            .lambdaLiteral(
                params: [fixture.interner.intern("cont")],
                body: lambdaBody,
                range: range
            ),
            type: blockType,
            fixture: fixture
        )
        let calleeExpr = appendTypedExpr(
            .nameRef(fixture.interner.intern("suspendCoroutineUninterceptedOrReturn"), range),
            type: anyType,
            fixture: fixture
        )
        let callExpr = appendTypedExpr(
            .call(
                callee: calleeExpr,
                typeArgs: [],
                args: [CallArgument(expr: lambdaExpr)],
                range: range
            ),
            type: anyType,
            fixture: fixture
        )

        fixture.bindings.markStdlibSpecialCallExpr(callExpr, kind: .suspendCoroutineUninterceptedOrReturn)

        var emit = KIRLoweringEmitContext()
        _ = fixture.driver.callLowerer.lowerCallExpr(
            callExpr,
            calleeExpr: calleeExpr,
            args: [CallArgument(expr: lambdaExpr)],
            ast: fixture.ast,
            sema: fixture.sema,
            arena: fixture.kirArena,
            interner: fixture.interner,
            propertyConstantInitializers: [:],
            instructions: &emit.instructions
        )

        let callees = extractCallees(from: emit.instructions, interner: fixture.interner)
        #expect(callees.contains("kk_coroutine_suspended"))
        #expect(emit.instructions.contains { instruction in
            if case .returnValue = instruction { return true }
            return false
        })
        #expect(emit.instructions.contains { instruction in
            if case .jumpIfEqual = instruction { return true }
            return false
        })
    }
}
#endif
