@JvmInline value class RefValue(val ref: Holder)
class Holder(val name: String)

fun check(v: RefValue?, expected: Holder) {
    println(v == null)
    println(v?.ref?.name)
    println(v?.ref === expected)
    println(v?.ref === v?.ref)
    if (v != null) {
        println(v.ref.name)
        println(v.ref === expected)
        println(v!!.ref === expected)
    }
}

fun main() {
    val payload = Holder("shared")
    val value: RefValue = RefValue(payload)
    println(value.ref.name)
    println(value.ref === payload)
    check(value, payload)
    check(null, payload)
    val erased: Any = value
    println((erased as? RefValue)?.ref?.name)
    println((erased as? RefValue)?.ref === payload)
}
