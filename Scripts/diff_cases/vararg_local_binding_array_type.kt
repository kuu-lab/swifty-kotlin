// KUU-3241: a vararg parameter's local binding must have the packed array
// type — not a classType built on the same-named constructor-function
// symbol (kotlin.IntArray names both a class and `fun IntArray(size)`).
// KOTLINC_FLAGS: -Xjdk-release=17
fun readInts(vararg xs: Int): IntArray = xs
fun readLongs(vararg xs: Long): LongArray = xs
fun readStrings(vararg xs: String): Array<out String> = xs
fun readBooleans(vararg xs: Boolean): BooleanArray = xs
fun <T> readGeneric(vararg xs: T): Array<out T> = xs

class Holder(vararg val values: Int) {
    fun read(): IntArray = values
}

fun main() {
    println(readInts(1, 2).size)
    println(readLongs(3L).size)
    println(readStrings("a", "b").size)
    println(readBooleans(true).size)
    println(readGeneric(1.5, 2.5).size)
    println(Holder(7, 8, 9).read().size)
}
