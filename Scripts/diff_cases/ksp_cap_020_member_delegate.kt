import kotlin.reflect.KProperty

class MemberHolder(val value: String) {
    operator fun getValue(thisRef: Any?, property: KProperty<*>): String = value
}

val member: String by MemberHolder("member")

fun main() {
    println(member)
}
