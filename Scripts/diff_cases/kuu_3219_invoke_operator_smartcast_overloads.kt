operator fun String.invoke(unused: String): String = "String.invoke(String)"
operator fun String.invoke(unused: Any): String = "String.invoke(Any)"
operator fun Any.invoke(unused: String): String = "Any.invoke(String)"

fun implicitArgumentCast(): String {
    val a: Any = ""
    return a(a as String)
}
fun explicitArgumentCast(): String {
    val a: Any = ""
    return a.invoke(a as String)
}
fun implicitReceiverCast(): String {
    val a: Any = ""
    return (a as String)(a)
}
fun explicitReceiverCast(): String {
    val a: Any = ""
    return (a as String).invoke(a)
}
fun implicitInvokeExplicitRecieverArgumentCast(): String {
    val a: Any = ""
    with (a) {
        return this(this as String)
    }
}
fun explicitInvokeImplicitRecieverArgumentCast(): String {
    val a: Any = ""
    with (a) {
        return invoke(this as String)
    }
}
fun explicitInvokeExplicitRecieverArgumentCast(): String {
    val a: Any = ""
    with (a) {
        return this.invoke(this as String)
    }
}
fun invokeReceiverSmartcast(): String {
    val a: Any = ""
    return when (val result = a(a as String)) {
        "Any.invoke(String)" -> "OK"
        else -> result
    }
}

fun main() {
    println(implicitArgumentCast())
    println(explicitArgumentCast())
    println(implicitReceiverCast())
    println(explicitReceiverCast())
    println(implicitInvokeExplicitRecieverArgumentCast())
    println(explicitInvokeImplicitRecieverArgumentCast())
    println(explicitInvokeExplicitRecieverArgumentCast())
    println(invokeReceiverSmartcast())
}
