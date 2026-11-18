#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

// MARK: - Outer stable-property smart cast inside an object literal member
//
// Targets: Sema/TypeCheck/ExprTypeChecker+ObjectLiteralInference.swift
//          Sema/DataFlow/Analysis+StableReferences.swift `resolveStableReference`
//
// KUU-4606: an object literal member captures the enclosing function's
// receiver *value*, but the enclosing class's outer-receiver tower entry
// carried the class symbol. Smart-cast flow references are keyed by the
// receiver value symbol (`receiverParameterSymbol(for:)`), so
// `resolveStableReference` returned nil and the non-null smart cast on the
// captured `this` was dropped inside the object literal's member bodies.
// kotlinc keeps the cast. Inferred returns (`fun read() = stable`) are the
// sharpest probe: they infer `String?` instead of `String` when the cast is
// lost.

extension DataFlowAndSemaRegressionTests {

    private static let objectLiteralOuterSmartCastSources: [String] = [
        // sample0 — explicit return type: the smart cast must narrow `stable`
        // to String inside the object literal member.
        """
        package ols0
        class Outer {
            val stable: String? = "ok"
            fun f() {
                if (stable != null) {
                    val o = object {
                        fun read(): String = stable
                    }
                    val s: String = o.read()
                }
            }
        }
        """,
        // sample1 — inferred return type: `read()` must infer String, not
        // String?, so the typed assignment only passes when the cast survives.
        """
        package ols1
        class Outer {
            val stable: String? = "ok"
            fun f() {
                if (stable != null) {
                    val o = object {
                        fun read() = stable
                    }
                    val s: String = o.read()
                }
            }
        }
        """,
        // sample2 — block-body member.
        """
        package ols2
        class Outer {
            val stable: String? = "ok"
            fun f() {
                if (stable != null) {
                    val o = object {
                        fun read(): String {
                            return stable
                        }
                    }
                    val s: String = o.read()
                }
            }
        }
        """,
        // sample3 — negative control: a mutable outer property must NOT be
        // smart-cast (kotlinc rejects it too), so `read()` stays String? and
        // the typed assignment must report SEMA-0468.
        """
        package ols3
        class Outer {
            var mutable: String? = "ok"
            fun f() {
                if (mutable != null) {
                    val o = object {
                        fun read() = mutable
                    }
                    val s: String = o.read()
                }
            }
        }
        """,
    ]

    private static nonisolated(unsafe) var _objectLiteralOuterSmartCastCtx: (CompilationContext, [String])?

    private func objectLiteralOuterSmartCastCtx() throws -> (CompilationContext, [String]) {
        if let cached = Self._objectLiteralOuterSmartCastCtx { return cached }
        var result: (CompilationContext, [String])?
        try withTemporaryFiles(contents: Self.objectLiteralOuterSmartCastSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = (ctx, paths)
        }
        let ctx = try #require(result)
        Self._objectLiteralOuterSmartCastCtx = ctx
        return ctx
    }

    @Test
    func objectLiteralMemberKeepsOuterStableSmartCast() throws {
        let (ctx, paths) = try objectLiteralOuterSmartCastCtx()
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
