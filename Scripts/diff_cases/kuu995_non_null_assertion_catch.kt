fun requireString(value: String?): String = value!!
fun requireInt(value: Int?): Int = value!!

fun main() {
    try {
        val x: String? = null
        x!!
        println("unreachable String")
    } catch (e: NullPointerException) {
        println("NPE caught")
    }

    try {
        val x: Int? = null
        println(x!!)
        println("unreachable Int")
    } catch (e: Exception) {
        println("E caught: " + (e is NullPointerException))
    } catch (t: Throwable) {
        println("wrong fallback")
    }

    try {
        val x: Int? = null
        println(x!!)
    } catch (t: Throwable) {
        println("T caught: " + (t is NullPointerException))
    }

    try {
        val x: Int? = null
        x!!
        println("unreachable standalone Int")
    } catch (e: IllegalArgumentException) {
        println("wrong sibling")
    } catch (e: NullPointerException) {
        println("Int NPE caught")
    } catch (e: Exception) {
        println("wrong superclass")
    }

    try {
        println(requireString(null))
    } catch (e: NullPointerException) {
        println("String function caught")
    }

    try {
        println(requireInt(null))
    } catch (e: NullPointerException) {
        println("Int function caught")
    }

    try {
        try {
            val x: Int? = null
            x!!
            println("unreachable nested")
        } catch (e: IllegalArgumentException) {
            println("wrong nested sibling")
        } finally {
            println("inner finally")
        }
    } catch (e: NullPointerException) {
        println("outer NPE caught")
    } finally {
        println("outer finally")
    }

    val text: String? = "ok"
    val number: Int? = 42
    println(text!!)
    println(number!!)
    println("end")
}
