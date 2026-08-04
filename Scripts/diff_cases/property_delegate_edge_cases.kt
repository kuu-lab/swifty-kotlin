import kotlin.properties.Delegates

class Holder {
    var initCount = 0
    val label = "holder"

    val token: String by lazy {
        initCount += 1
        "ready"
    }

    var observed: Int by Delegates.observable(1) { _, old, new ->
        initCount += 1
        println("$label:$old->$new:$initCount")
    }

    var guarded: Int by Delegates.vetoable(0) { _, _, new ->
        new >= initCount
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
