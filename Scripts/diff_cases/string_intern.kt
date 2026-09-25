fun main() {
    val a = "he" + "llo"
    println(a.intern() == "hello")
    println("already".intern() == "already")
}
