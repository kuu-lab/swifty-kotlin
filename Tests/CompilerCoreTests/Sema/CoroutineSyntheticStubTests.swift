@testable import CompilerCore
import Foundation
import XCTest

final class CoroutineSyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testEmptyCoroutineContextIsRegisteredAsSyntheticObject() throws {
        let (sema, interner) = try makeSema()

        let coroutineContextFQName = ["kotlin", "coroutines", "CoroutineContext"].map { interner.intern($0) }
        let coroutineContextSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: coroutineContextFQName),
            "Expected kotlin.coroutines.CoroutineContext to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(coroutineContextSymbol)?.kind, .interface)

        let emptyCoroutineContextFQName = ["kotlin", "coroutines", "EmptyCoroutineContext"].map { interner.intern($0) }
        let emptyCoroutineContextSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: emptyCoroutineContextFQName),
            "Expected kotlin.coroutines.EmptyCoroutineContext to be registered"
        )
        let emptyCoroutineContextInfo = try XCTUnwrap(sema.symbols.symbol(emptyCoroutineContextSymbol))
        XCTAssertEqual(emptyCoroutineContextInfo.kind, .object)
        XCTAssertTrue(emptyCoroutineContextInfo.flags.contains(.synthetic))

        let expectedEmptyCoroutineContextType = sema.types.make(.classType(ClassType(
            classSymbol: emptyCoroutineContextSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(
            sema.symbols.propertyType(for: emptyCoroutineContextSymbol),
            expectedEmptyCoroutineContextType
        )
        XCTAssertEqual(
            sema.symbols.directSupertypes(for: emptyCoroutineContextSymbol),
            [coroutineContextSymbol]
        )
    }

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

            XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty)
        }
    }

    func testSuspendCoroutineUninterceptedOrReturnStubIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "coroutines", "intrinsics", "suspendCoroutineUninterceptedOrReturn"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))
        XCTAssertEqual(info.kind, .function)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertTrue(info.flags.contains(.inlineFunction))
        XCTAssertTrue(info.flags.contains(.suspendFunction))

        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        XCTAssertTrue(signature.isSuspend)
        XCTAssertEqual(signature.typeParameterSymbols.count, 1)
        XCTAssertEqual(signature.parameterTypes.count, 1)

        let continuationFQName = ["kotlin", "coroutines", "Continuation"].map { interner.intern($0) }
        let continuationSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: continuationFQName))
        XCTAssertEqual(sema.types.nominalTypeParameterSymbols(for: continuationSymbol).count, 1)
        let typeParamSymbol = try XCTUnwrap(signature.typeParameterSymbols.first)
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

        XCTAssertEqual(signature.parameterTypes.first, expectedBlockType)
        XCTAssertEqual(signature.returnType, typeParamType)
    }

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

            XCTAssertFalse(ctx.diagnostics.hasError)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "suspendCoroutineUninterceptedOrReturn"
            })

            XCTAssertNil(sema.bindings.stdlibSpecialCallKind(for: callExpr))
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let chosenInfo = try XCTUnwrap(sema.symbols.symbol(chosenCallee))
            XCTAssertFalse(chosenInfo.flags.contains(.synthetic))
        }
    }

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

            XCTAssertFalse(ctx.diagnostics.hasError)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "suspendCoroutineUninterceptedOrReturn"
            })

            XCTAssertEqual(sema.bindings.stdlibSpecialCallKind(for: callExpr), .suspendCoroutineUninterceptedOrReturn)
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let chosenInfo = try XCTUnwrap(sema.symbols.symbol(chosenCallee))
            XCTAssertEqual(chosenInfo.fqName, [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("coroutines"),
                ctx.interner.intern("intrinsics"),
                ctx.interner.intern("suspendCoroutineUninterceptedOrReturn"),
            ])
        }
    }
}
