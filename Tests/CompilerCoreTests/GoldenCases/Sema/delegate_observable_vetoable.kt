package golden.sema

import kotlin.properties.Delegates

var name: String by Delegates.observable("initial") { prop, old, new ->
    println("changed from $old to $new")
}

var age: Int by Delegates.vetoable(0) { prop, old, new ->
    new >= 0
}

fun main() {
    println(name)
    name = "updated"
    println(name)
    println(age)
    age = 10
    println(age)
}
