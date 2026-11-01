// `override` members of final owners are effectively final, so kotlinc
// permits `inline` on backing-field-less accessors (KUU-4110).
interface HasZero { val zero: Int }
class Impl : HasZero { override inline val zero: Int get() = 0 }
object Obj : HasZero { override inline val zero: Int get() = 1 }
enum class E : HasZero { A { override inline val zero: Int get() = 2 } }
var backing = 10

class Holder {
    inline var value: Int
        get() = backing
        set(v) { backing = v }
}

fun main() {
    println(Impl().zero)
    println(Obj.zero)
    println(E.A.zero)
    val h = Holder()
    h.value = 7
    println(h.value)
}
