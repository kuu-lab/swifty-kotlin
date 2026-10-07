import kotlin.properties.Delegates

var observed: String by Delegates.observable("initial") { _, old, new ->
    println("observed:$old->$new")
}

var accepted: Int by Delegates.vetoable(0) { _, old, new ->
    println("veto check:$old->$new")
    new >= 0
}

var late: String by Delegates.notNull()

class Holder {
    var changes = 0
    var count: Int by Delegates.observable(0) { _, old, new ->
        changes += 1
        println("holder:$old->$new:$changes")
    }
    var threshold: Int = 0
    var guarded: Int by Delegates.vetoable(1) { _, _, new -> new >= threshold }
    var name: String by Delegates.notNull()
}

fun main() {
    println(observed)
    observed = "updated"
    println(observed)

    accepted = 5
    println(accepted)
    accepted = -3
    println(accepted)

    try {
        println(late)
    } catch (error: IllegalStateException) {
        println(error.message)
    }
    late = "ready"
    println(late)

    val holder = Holder()
    holder.count = 2
    holder.count = 2
    println(holder.changes)

    holder.threshold = 4
    holder.guarded = 3
    println(holder.guarded)
    holder.guarded = 7
    println(holder.guarded)

    holder.name = "holder-name"
    println(holder.name)
}
