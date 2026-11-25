// DIFF_JVM
// String.format is a companion member in the Kotlin stdlib. The real stdlib
// ships it @InlineOnly (no bytecode), so the compiler must still bind the
// companion overload and lower it to java/lang/String.format. Previously the
// call fell back to the String.format extension and coerced the companion
// object to String, crashing with a ClassCastException at runtime.
fun main() {
    println(String.format("%08x", 255))
    println(String.format("%s-%d", "ab", 7))
    println(String.format("%.2f", 3.14159))
    println(String.format("%s", null))
}
