#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

// MARK: - Outer stable-property smart cast inside a local class member
//
// Targets: Sema/TypeCheck/ExprTypeChecker+LocalNominalInference.swift
//          Sema/DataFlow/Analysis+StableReferences.swift `resolveStableReference`
//
// KUU-4605: a function-local class captures the enclosing function's receiver
// *value*. The enclosing class's outer-receiver tower entry carries the class
// symbol, but smart-cast flow references are keyed by the receiver value symbol
// (`receiverParameterSymbol(for:)`), so `resolveStableReference` returned nil
// and the non-null smart cast on the captured `this` was dropped inside the
// local class's member bodies. kotlinc keeps the cast. Explicit-return members
// were masked by the speculative member double-check (DEBT-SEMA-001); inferred
// returns (`fun read() = stable`) genuinely inferred `String?` and failed.

extension DataFlowAndSemaRegressionTests {

    private static let localClassOuterSmartCastSources: [String] = [
        // sample0 — explicit return type: the smart cast must narrow `stable`
        // to String inside the local class member.
        """
        package lcs0
        class Outer {
            val stable: String? = "ok"
            fun f() {
                if (stable != null) {
                    class Local {
                        fun read(): String = stable
                    }
                    val s: String = Local().read()
                }
            }
        }
        """,
        // sample1 — inferred return type: `read()` must infer String, not
        // String?, so the typed assignment only passes when the cast survives.
        """
        package lcs1
        class Outer {
            val stable: String? = "ok"
            fun f() {
                if (stable != null) {
                    class Local {
                        fun read() = stable
                    }
                    val s: String = Local().read()
                }
            }
        }
        """,
        // sample2 — block-body member and a captured local val.
        """
        package lcs2
        fun f() {
            val captured: String? = "local"
            if (captured != null) {
                class Local {
                    fun read(): String {
                        return captured
                    }
                }
                val s: String = Local().read()
            }
        }
        """,
        // sample3 — negative control: a mutable outer property must NOT be
        // smart-cast (kotlinc rejects it too), so `read()` stays String? and
        // the typed assignment must report SEMA-0468.
        """
        package lcs3
        class Outer {
            var mutable: String? = "ok"
            fun f() {
                if (mutable != null) {
                    class Local {
                        fun read() = mutable
                    }
                    val s: String = Local().read()
                }
            }
        }
        """,
    ]

    private static nonisolated(unsafe) var _localClassOuterSmartCastCtx: (CompilationContext, [String])?

    private func localClassOuterSmartCastCtx() throws -> (CompilationContext, [String]) {
        if let cached = Self._localClassOuterSmartCastCtx { return cached }
        var result: (CompilationContext, [String])?
        try withTemporaryFiles(contents: Self.localClassOuterSmartCastSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = (ctx, paths)
        }
        let ctx = try #require(result)
        Self._localClassOuterSmartCastCtx = ctx
        return ctx
    }

    @Test
    func localClassMemberKeepsOuterStableSmartCast() throws {
        let (ctx, paths) = try localClassOuterSmartCastCtx()
        for path in paths.prefix(3) {
            let diagnostics = diagnosticsForPath(path, in: ctx)
            #expect(diagnostics.isEmpty, "Unexpected diagnostics: \(diagnostics.map(\.code))")
        }
        // sample3 is the negative control: the mutable property legitimately
        // blocks the cast, so the initializer mismatch must still fire.
        let mutableDiagnostics = diagnosticsForPath(paths[3], in: ctx)
        #expect(
            mutableDiagnostics.contains { $0.code == "KSWIFTK-SEMA-0468" },
            "Mutable outer property must keep reporting SEMA-0468: \(mutableDiagnostics.map(\.code))"
        )
    }
}
#endif
