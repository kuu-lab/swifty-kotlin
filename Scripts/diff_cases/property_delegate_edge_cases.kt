// SKIP-DIFF (DEBT-DIFF-005): class-member property delegates are broken in two independent ways.
// (1) BUG-151: Delegates.observable/vetoable callback lambda bodies are dropped entirely during
// KIR lowering (the callback becomes a no-op that just returns Unit/false), so neither the
// println side effect nor vetoable's accept/reject logic ever runs. (2) BUG-168: a bare-name
// (implicit `this`) compound assign of an outer instance field from inside a delegate
// initializer lambda (`lazy { initCount += 1; ... }`) does not persist to the real field, even
// though the same pattern inside an ordinary closure (`run { field += 1 }`) works correctly —
// this is specific to the delegate-body lowering path, not a general closure-capture bug.
// Re-run with --force-run-skipped once BUG-151/BUG-168 land to confirm full parity.
import kotlin.properties.Delegates

class Holder {
    var initCount = 0

    val token: String by lazy {
        initCount += 1
        "ready"
    }

    var observed: Int by Delegates.observable(1) { _, old, new ->
        println("obs:$old->$new")
    }

    var guarded: Int by Delegates.vetoable(0) { _, _, new ->
        new >= 0
    }
}

fun main() {
    val holder = Holder()
    println(holder.initCount)
    println(holder.token)
    println(holder.token)
    println(holder.initCount)

    holder.observed = 2
    holder.observed = 5

    holder.guarded = 3
    println(holder.guarded)
    holder.guarded = -1
    println(holder.guarded)
}
