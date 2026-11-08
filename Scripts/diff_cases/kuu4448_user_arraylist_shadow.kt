// KUU-4448: a user class that shares a collection constructor name keeps
// ordinary resolution and its own object identity — the lowering pass must
// not rewrite it to the stdlib runtime list bridge.
class ArrayList {
    val tag = "user"
    fun hello() = "hi"
}

fun main() {
    val u = ArrayList()
    println(u.tag)
    println(u.hello())
}
