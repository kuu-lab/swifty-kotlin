import kotlin.reflect.KProperty

class LocalDelegate
fun localOnly() {
    operator fun LocalDelegate.getValue(thisRef: Any?, property: KProperty<*>): Int = 3
    val answer by LocalDelegate()
    println(answer)
}

class OuterDelegate
operator fun OuterDelegate.getValue(thisRef: Any?, property: KProperty<*>): Int = 1
fun nonOperatorFallback() {
    fun OuterDelegate.getValue(thisRef: Any?, property: KProperty<*>): Int = 4
    val answer by OuterDelegate()
    println(answer)
}
fun ordinaryLocalCall() {
    fun OuterDelegate.read(): Int = 4
    println(OuterDelegate().read())
}
fun inapplicableLocalFallback() {
    operator fun OuterDelegate.getValue(thisRef: String, property: KProperty<*>): Int = 0
    val answer by OuterDelegate()
    println(answer)
}

class MemberDelegate {
    operator fun getValue(thisRef: Any?, property: KProperty<*>): Int = 9
}
fun memberPriority() {
    operator fun MemberDelegate.getValue(thisRef: Any?, property: KProperty<*>): Int = 0
    val answer by MemberDelegate()
    println(answer)
}
class Owner {
    operator fun LocalDelegate.getValue(thisRef: Any?, property: KProperty<*>): Int = 7
    fun localPriority() {
        operator fun LocalDelegate.getValue(thisRef: Any?, property: KProperty<*>): Int = 8
        val answer by LocalDelegate()
        println(answer)
    }
}

class MutableDelegate(var value: Int)
fun mutableLocalOperators() {
    operator fun MutableDelegate.provideDelegate(thisRef: Any?, property: KProperty<*>): MutableDelegate = MutableDelegate(13)
    operator fun MutableDelegate.getValue(thisRef: Any?, property: KProperty<*>): Int = value
    operator fun MutableDelegate.setValue(thisRef: Any?, property: KProperty<*>, newValue: Int) { value = newValue }
    var answer by MutableDelegate(0)
    println(answer)
    answer = 14
    println(answer)
}

fun main() {
    localOnly()
    nonOperatorFallback()
    ordinaryLocalCall()
    inapplicableLocalFallback()
    memberPriority()
    Owner().localPriority()
    mutableLocalOperators()
}
