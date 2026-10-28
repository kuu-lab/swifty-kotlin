// DIFF_JVM: exercise both operator and case-insensitive CharSequence.contains overloads.
fun main() {
    val sequence: CharSequence = "AbCd"
    println("Ab" in sequence)
    println("bc" in sequence)
    println('b' in sequence)
    println('a' in sequence)
    println(sequence.contains(other = "bc", ignoreCase = true))
    println(sequence.contains(char = 'a', ignoreCase = true))
    println(sequence.contains("Ab"))
    println(sequence.contains('b'))
}
