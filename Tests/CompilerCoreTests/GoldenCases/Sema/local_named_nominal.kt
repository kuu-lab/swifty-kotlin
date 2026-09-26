package golden.sema

fun useLocalClass(): Int {
    class Local(val v: Int)
    val l = Local(5)
    return l.v
}

fun useLocalObject(): Int {
    object Local {
        val v = 5
    }
    return Local.v
}
