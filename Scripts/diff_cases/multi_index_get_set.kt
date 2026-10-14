// KUU-2075: Multi-index operators must call the selected overload.
// KOTLINC_FLAGS: -Xjdk-release=17
operator fun Array<String>.get(a: Int, b: Int) = this[a + b]
operator fun Array<String>.set(a: Int, b: Int, value: String) { this[a + b] = value }
operator fun <T> List<T>.get(a: Int, b: Int): T = this[a + b]
operator fun <T> MutableList<T>.set(a: Int, b: Int, value: T) { this[a + b] = value }
operator fun IntArray.get(a: Int, b: Int): Int = this[a + b]
operator fun IntArray.set(a: Int, b: Int, value: Int) { this[a + b] = value }

fun main() {
    // Preserve the issue's exact Array-constructor reproducer.
    val s = Array(1){""}; println(s[0,0])
    val strings = arrayOf("a", "b", "c")
    println(strings[1,1])
    strings[0,1] = "B"
    println(strings[1])
    println(strings.get(0,1))
    strings.set(1,1,"C")
    println(strings[1,1])
    val list = mutableListOf("d", "e", "f")
    println(list[1,1])
    list[0,1] = "E"
    println(list[0,1])
    val ints = intArrayOf(10,20,30)
    println(ints[1,1])
    ints[0,1] = 21
    println(ints[0,1])
}
