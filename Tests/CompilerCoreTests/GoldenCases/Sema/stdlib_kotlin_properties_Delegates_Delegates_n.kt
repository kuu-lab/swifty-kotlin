package golden.sema

import kotlin.properties.Delegates

var observed: String by Delegates.observable("initial") { prop, old, new ->
    println("changed from $old to $new")
}

var accepted: Int by Delegates.vetoable(0) { prop, old, new ->
    new >= 0
}

var late: String by Delegates.notNull()

fun readValues(): String {
    late = "set"
    return "$observed/$accepted/$late"
}
