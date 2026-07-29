// BUG-145: substring(...) with an implicit receiver inside a String extension
// must behave identically to the explicit this.substring(...) form.
fun String.dropPrefix(n: Int): String = substring(n)

fun String.middle(start: Int, end: Int): String = substring(start, end)

fun String.explicitDropPrefix(n: Int): String = this.substring(n)

fun main() {
    println("hello".dropPrefix(2))
    println("hello".middle(1, 3))
    println("hello".explicitDropPrefix(2))
    println("hello".dropPrefix(0))
    println("hello".dropPrefix(5))
}
