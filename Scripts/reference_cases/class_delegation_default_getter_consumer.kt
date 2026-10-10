import delegation.*
class MutableFlag : Flag { override var value = true }
class Child(original: Flag) : Wrapped(original)
fun main() {
    val original = MutableFlag()
    val wrapped = Wrapped(original)
    val dynamic: Flag = wrapped
    println(dynamic.value)
    println(wrapped.value)
    println(Child(original).value)
    original.value = false
    println(dynamic.value)
    println(Child(original).value)
    println(Wrapped(DefaultFlag()).value)
    println(Wrapped(KnownFlag()).value)
}
