// DIFF_JVM
// WITH_STDLIB

fun interface KRunnable {
    fun invoke()
}

fun isNull(r: KRunnable?): Boolean {
    if (r == null) return true
    r.invoke()
    return false
}

fun nullableFun(fromNull: Boolean): (() -> Unit)? =
    if (fromNull) null else {{}}

fun box(): String {
    if (!isNull(nullableFun(true))) return "Fail 1"
    if (isNull(nullableFun(false))) return "Fail 2"
    if (!isNull(null)) return "Fail 3"
    if (isNull {}) return "Fail 4"
    return "OK"
}

fun take(r: KRunnable?): Boolean {
    r?.invoke()
    return r != null
}

fun minimum(): Boolean {
    val absent: (() -> Unit)? = null
    if (take(absent)) return false
    val callback: (() -> Unit)? = {}
    return take(callback)
}

fun control(): Boolean {
    val callback: () -> Unit = {}
    return take(callback) && !take(null) && take {}
}

fun main() {
    println(if (box() == "OK" && minimum() && control()) "OK" else "FAIL")
}
