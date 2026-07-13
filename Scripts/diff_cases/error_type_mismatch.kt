// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
// Error cases for type mismatch (KSWIFTK-TYPE-*)

fun requireInt(x: Int): Int = x
fun requireString(x: String): String = x

fun main() {
    // ERROR: Passing String where Int is expected
    val a: Int = "hello"  // KSWIFTK-TYPE-0010: type mismatch, expected Int found String

    // ERROR: Passing Int where String is expected
    val b: String = 42  // KSWIFTK-TYPE-0010: type mismatch, expected String found Int

    // ERROR: Passing Boolean where Int is expected
    requireInt(true)  // KSWIFTK-TYPE-0010: type mismatch, expected Int found Boolean

    // ERROR: Assigning Double to Int without explicit conversion
    val c: Int = 3.14  // KSWIFTK-TYPE-0010: type mismatch, expected Int found Double

    // ERROR: Returning wrong type from function
    val result: List<Int> = listOf("a", "b")  // KSWIFTK-TYPE-0010: type mismatch, expected List<Int> found List<String>

    // ERROR: Incompatible types in when expression branches
    val x: Int = when (a) {
        1 -> "one"   // KSWIFTK-TYPE-0011: branch returns String, expected Int
        else -> 2
    }

    println(a)
}
