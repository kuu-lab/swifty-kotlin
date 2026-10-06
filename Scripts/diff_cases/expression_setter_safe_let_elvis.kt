class V<T : Any> {
    var stored: T? = null
    var flag = false
    var value: T?
        get() = stored
        set(p) = p?.let { stored = it; flag = false } ?: run { flag = true }
}

fun main() {
    val v = V<String>()
    v.value = "first"
    println(v.value)
    println(v.flag)
    v.value = null
    println(v.value)
    println(v.flag)
    v.value = "second"
    println(v.value)
    println(v.flag)
}
