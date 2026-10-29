// KUU-3740: the object body remains attached when it starts on the next line.
interface NewlineListener { fun value(): String }

fun returnedListener(): NewlineListener {
    return object : NewlineListener
    { override fun value() = "returned" }
}

fun invokeBlock(block: () -> String): String = block()

fun main() {
    val listener: NewlineListener = object : NewlineListener
    { override fun value() = "multiline" }
    var mutable = object : NewlineListener
    { override fun value() = "mutable" }
    val complete = object : NewlineListener { override fun value() = "complete" }
    { println("unused after object") }
    val value = Unit
    { println("unused after Unit") }
    println(listener.value())
    println(mutable.value())
    println(returnedListener().value())
    println(complete.value())
    println(invokeBlock()
        { "call" })
}
