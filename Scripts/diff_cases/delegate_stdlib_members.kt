import kotlin.properties.Delegates

class User {
    var name: String by Delegates.observable("initial") { _, old, new ->
        println("changed from $old to $new")
    }
    var count: Int by Delegates.vetoable(0) { _, _, new -> new >= 0 }
    var late: String by Delegates.notNull()
}

var topName: String by Delegates.observable("t0") { _, old, new -> println("top $old->$new") }
var topCount: Int by Delegates.vetoable(1) { _, _, new -> new > 0 }

fun main() {
    val u = User()
    u.name = "hello"
    println(u.name)
    u.name = "world"
    println(u.name)

    u.count = 5
    println(u.count)
    u.count = -1
    println(u.count)
    u.count += 3
    println(u.count)

    u.late = "abc"
    println(u.late)
    u.late = "def"
    println(u.late)

    topName = "t1"
    println(topName)
    topCount = 9
    println(topCount)
    topCount = -5
    println(topCount)
}
