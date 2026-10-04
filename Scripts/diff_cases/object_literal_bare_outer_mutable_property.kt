// KSP-CAP-001 (follow-up): an object literal's member function reading or
// writing an enclosing class's mutable property through a bare (unqualified)
// name has no explicit receiver expression to lower, unlike `this.counter`.
// Sema's `capturesMutableOuterProperty` mechanism (ExprTypeChecker+
// ObjectLiteralInference.swift) captures the enclosing receiver for exactly
// this case, but two gaps let the KIR still use the wrong instance:
//   1. A bare read resolved via plain lexical scope lookup (not
//      `resolveImplicitReceiverMember`) never set `implicitReceiverMemberNames`,
//      so ExprLowerer+ControlFlowAndBlocks.swift's generic field-offset read
//      branch used the object literal's own receiver instead of walking the
//      captured outer-receiver chain.
//   2. A bare write-only reference (`counter = 1` or `counter += 1` with no
//      accompanying read anywhere in the body) was invisible to
//      `CaptureAnalyzer.collectCapturedOuterSymbols`, which only recorded
//      `.nameRef` reads, so no capture slot was ever allocated at all.
// Both previously crashed with `KSWIFTK-RUNTIME-0001: kk_array_get_inbounds
// precondition failed` (bare read) or an unhandled out-of-bounds exception
// (write-only), because the field offset is computed against the enclosing
// class's layout but applied to the much smaller object-literal instance.
class Outer(val tag: String) {
    var counter: Int = 5

    fun bareRead(): Int {
        val obj = object {
            fun show(): Int {
                return counter
            }
        }
        return obj.show()
    }

    fun bareWriteOnly(): Int {
        val obj = object {
            fun bump() {
                counter = 42
            }
        }
        obj.bump()
        return this.counter
    }

    fun bareCompoundAssign(): Int {
        val obj = object {
            fun bump(): Int {
                counter += 1
                return counter
            }
        }
        return obj.bump()
    }
}

fun main() {
    println(Outer("a").bareRead())
    println(Outer("b").bareWriteOnly())
    println(Outer("c").bareCompoundAssign())
}
