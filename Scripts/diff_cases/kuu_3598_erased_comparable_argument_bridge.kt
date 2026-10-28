// KUU-3598: an unchecked Comparable<Any> cast must still dispatch through the
// Foo.compareTo bridge, which checks the erased argument against Foo.
class Foo(val s: String) : Comparable<Foo> {
    override fun compareTo(other: Foo) = s.compareTo(other.s)
}

fun main() {
    val x = Foo("1") as Comparable<Any>
    try {
        println("FAIL: ${x.compareTo(2)}")
    } catch (e: ClassCastException) {
        println("OK")
    }
    println(x.compareTo(Foo("2")))
}
