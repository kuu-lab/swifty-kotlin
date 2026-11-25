#if canImport(Testing)
@testable import CompilerCore
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

    private static let positiveObjectLiteralOuterSmartCastSources: [String] = [
        // explicit return type: the smart cast must narrow `stable` to String
        // inside the object literal member.
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
        // inferred return type: `read()` must infer String, not String?, so the
        // typed assignment only passes when the cast survives.
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
        // block-body member.
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
    ]

    private static let mutableObjectLiteralOuterSmartCastSource = """
    // A mutable outer property is not a stable smart-cast root, so `read()`
    // stays String? and the typed assignment must still report SEMA-0468.
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
    """

    @Test
    func objectLiteralMemberKeepsOuterStableSmartCast() throws {
        _ = try semaContext(from: Self.positiveObjectLiteralOuterSmartCastSources)
        _ = try semaContext(
            from: Self.mutableObjectLiteralOuterSmartCastSource,
            expecting: [.error("KSWIFTK-SEMA-0468")]
        )
    }
}
#endif
