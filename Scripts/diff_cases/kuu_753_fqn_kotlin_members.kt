// KUU-753: Fully-qualified kotlin package references must resolve through
// class, object, and companion-member paths in expression position.
fun main() {
    println(kotlin.time.Duration.ZERO)
    println(kotlin.math.PI)
    // Pass the object through an existing API so this case stays focused on
    // FQN resolution rather than Charset.toString() formatting.
    println("hello".toByteArray(kotlin.text.Charsets.UTF_8).size)
}
