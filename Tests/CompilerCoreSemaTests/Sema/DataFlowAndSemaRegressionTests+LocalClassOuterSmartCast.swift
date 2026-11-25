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
        // sample4 — the local class sits inside a receiver lambda (`with`)
        // within a plain member function. The lambda has its own `this`
        // (String), but `enclosingFunctionSymbol` stays `f`, whose receiver is
        // the `Outer` instance, so the smart cast must survive (kotlinc accepts).
        """
        package lcs4
        class Outer {
            val stable: String? = "ok"
            fun f() {
                if (stable != null) {
                    with("lambda") {
                        class Local {
                            fun read(): String = stable
                        }
                        val s: String = Local().read()
                    }
                }
            }
        }
        """,
        // sample5 — member *extension*: the extension receiver (`this`, a
        // String) differs from the `Outer` dispatch receiver that owns
        // `stable`. kotlinc accepts the cast, but kswiftc conservatively keeps
        // rejecting it rather than risk binding the outer entry to the wrong
        // instance. Uses an inferred return so the loss is not masked by the
        // class-member double-check; pins the safe-rejection behaviour.
        """
        package lcs5
        class Outer {
            val stable: String? = "ok"
            fun String.ext() {
                if (stable != null) {
                    class Local {
                        fun read() = stable
                    }
                    val s: String = Local().read()
                }
            }
        }
        """,
        // sample6 — a receiver-less local function inside a receiver lambda
        // inside a member function. `enclosingFunctionSymbol` becomes the
        // local function, which has no `this`, so the rewrite must NOT bind
        // the outer entry to a non-existent receiver; kswiftc conservatively
        // rejects (SEMA-0468) rather than miscompile the captured instance.
        """
        package lcs6
        class Outer {
            val stable: String? = "ok"
            fun f() {
                if (stable != null) {
                    with("lambda") {
                        fun local() {
                            class Local {
                                fun read() = stable
                            }
                            val s: String = Local().read()
                        }
                        local()
                    }
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
        // samples 0,1,2,4 must keep the smart cast (plain member, inferred
        // return, block body, and inside a receiver lambda).
        for index in [0, 1, 2, 4] {
            let diagnostics = diagnosticsForPath(paths[index], in: ctx)
            #expect(diagnostics.isEmpty, "sample\(index) unexpected diagnostics: \(diagnostics.map(\.code))")
        }
        // samples 3 (mutable), 5 (member extension) and 6 (receiver-less local
        // function) must keep reporting SEMA-0468: the mutable property
        // legitimately blocks the cast, and the extension/local-function
        // receivers are not the `Outer` instance, so the cast is conservatively
        // rejected rather than risk reading the wrong receiver.
        for index in [3, 5, 6] {
            let diagnostics = diagnosticsForPath(paths[index], in: ctx)
            #expect(
                diagnostics.contains { $0.code == "KSWIFTK-SEMA-0468" },
                "sample\(index) must report SEMA-0468: \(diagnostics.map(\.code))"
            )
        }
    }
}
#endif
