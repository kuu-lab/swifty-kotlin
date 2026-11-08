#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct OverloadedGenericCallExpectedTypeTests {
    @Test
    func returnedLambdaImplicitItUsesOverloadedCallExpectedResult() throws {
        try withTemporaryFile(contents: """
        fun <R> generic(block: () -> R): R = block()
        fun <T, R> T.generic(block: T.() -> R): R = block()
        fun <R> single(block: () -> R): R = block()
        class Box<T>(val value: T) {
            fun <R> mapLike(block: (T) -> R): R = block(value)
        }
        val runFoo: ((String) -> String) = run { { it } }
        val foo: ((String) -> String) = generic { { it } }
        val noOverload: ((String) -> String) = single { { it } }
        val explicitInner: ((String) -> String) = generic { { value: String -> value } }
        val explicitResult: ((String) -> String) = generic<(String) -> String> { { it } }
        fun memberMap(box: Box<String>): String = box.mapLike { it }
        fun safeMemberMap(box: Box<String>?): String = box?.mapLike { it } ?: ""
        fun runBox(): String = runFoo("OK")
        fun box(): String = foo("OK")
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Expected the inner lambda's implicit `it` to infer as String, got: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    @Test
    func genuinelyAmbiguousOverloadRemainsRejected() throws {
        try withTemporaryFile(contents: """
        fun <R> ambiguous(block: () -> R, marker: String): R = block()
        fun <R> ambiguous(block: () -> R, marker: Int): R = block()
        val result: String = ambiguous({ "OK" }, TODO())
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0003" },
                "Expected incompatible overloads to remain ambiguous, got: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    @Test
    func uninferableGenericOverloadLosesToNonGenericCandidate() throws {
        // KUU-4466: `fun <T> kc(appDeclaration: Decl? = null)` declares `T`
        // but never mentions it, so `T` cannot be inferred from the call.
        // kotlinc drops the candidate and picks the non-generic overload
        // (koin `koinConfiguration { }` vs `koinConfiguration(declaration)`).
        try withTemporaryFile(contents: """
        typealias Decl = () -> Unit
        fun kc(declaration: Decl): String = "nongeneric"
        fun <T : Any> kc(appDeclaration: Decl? = null): Int = 2
        fun test(): Any = kc { }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Expected the non-generic overload to win, got: \(ctx.diagnostics.diagnostics)"
            )
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callIDs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let id = ExprID(rawValue: Int32(index))
                guard case let .call(callee, _, _, _) = ast.arena.expr(id),
                      case let .nameRef(name, _) = ast.arena.expr(callee),
                      ctx.interner.resolve(name) == "kc"
                else { return nil }
                return id
            }
            let callID = try #require(callIDs.first)
            let callType = try #require(sema.bindings.exprType(for: callID))
            #expect(
                sema.types.displayName(of: callType, symbols: sema.symbols, interner: ctx.interner) == "String",
                "Expected the non-generic `kc` (String) to be chosen"
            )
        }
    }

    @Test
    func soleUninferableGenericOverloadReportsInferDiagnostic() throws {
        // kotlinc rejects `baz { }` with "cannot infer type for type
        // parameter 'T'" even though `T` is unused; kswiftc now reports the
        // same SEMA-INFER instead of silently binding the phantom parameter.
        try withTemporaryFile(contents: """
        fun <T : Any> baz(d: (() -> Unit)? = null): Int = 2
        fun test(): Int = baz { }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-INFER" },
                "Expected SEMA-INFER for the uninferable type parameter, got: \(ctx.diagnostics.diagnostics)"
            )
        }
    }
}
#endif
