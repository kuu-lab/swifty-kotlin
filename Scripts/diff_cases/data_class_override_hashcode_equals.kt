data class Cust(val a: Int) {
    override fun equals(other: Any?) = other is Cust
    override fun hashCode() = 1
    override fun toString() = "Cust!"
}
data class OnlyHash(val a: Int) { override fun hashCode() = a * 7 }
data class OnlyEq(val a: Int) { override fun equals(other: Any?) = other is OnlyEq && other.a % 2 == a % 2 }

fun main() {
    println(Cust(1) == Cust(2)); println(Cust(1))
    println(Cust(1).copy(a = 9)); println(Cust(5).hashCode())
    println(OnlyHash(3).hashCode()); println(OnlyHash(3) == OnlyHash(3)); println(OnlyHash(3))
    println(OnlyEq(1) == OnlyEq(3)); println(OnlyEq(1) == OnlyEq(2)); println(OnlyEq(1))
}
