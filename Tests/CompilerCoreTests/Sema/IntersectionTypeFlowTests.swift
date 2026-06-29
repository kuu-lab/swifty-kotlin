#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct IntersectionTypeFlowTests {
    @Test func testIntersectionWithAnyMakesTypeParamDefinitelyNonNull() throws {
        let source = """
        fun <T : Any?> identity(x: T & Any): T & Any = x
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let xRef = try #require(firstExprID(in: ast) { _, expr in
                guard case let .nameRef(name, _) = expr else { return false }
                return ctx.interner.resolve(name) == "x"
            })
            let xType = try #require(sema.bindings.exprType(for: xRef))

            guard case let .intersection(parts) = sema.types.kind(of: xType) else {
                Issue.record("Expected intersection type for `x`, got \(sema.types.kind(of: xType))")
                return
            }

            let hasAny = parts.contains { sema.types.kind(of: $0) == .any(.nonNull) }
            let hasTypeParam = parts.contains {
                if case .typeParam = sema.types.kind(of: $0) {
                    return true
                }
                return false
            }

            #expect(hasAny)
            #expect(hasTypeParam)
            #expect(sema.types.isDefinitelyNonNull(xType))
            #expect(sema.types.nullability(of: xType) == .nonNull)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map(\.code))")
        }
    }

    @Test func testDefinitelyNonNullIntersectionReceiverSupportsDirectAndSafeCalls() throws {
        let source = """
        fun Any.id(): Int = 1

        fun <T : Any?> direct(x: T & Any): Int = x.id()
        fun <T : Any?> safe(x: T & Any): Int? = x?.id()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let directCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "id"
            })
            let safeCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .safeMemberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "id"
            })

            #expect(sema.bindings.exprType(for: directCall) == sema.types.intType)
            #expect(
                sema.bindings.exprType(for: safeCall) == sema.types.makeNullable(sema.types.intType)
            )
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map(\.code))")
        }
    }

    @Test func testIntersectionParameterInferenceAtCallSite() throws {
        let source = """
        fun Any.idTag(): Int = 7

        fun <T : Any?> directValue(x: T & Any): Int = x.idTag()
        fun <T : Any?> safeValue(x: T & Any): Int? = x?.idTag()

        fun main() {
            println(directValue("hello"))
            println(safeValue("world"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map(\.code))")
        }
    }
}
#endif
