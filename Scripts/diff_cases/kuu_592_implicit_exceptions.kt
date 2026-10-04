fun main() {
    try {
        val n: String? = null
        println(n!!.length)
    } catch (e: Throwable) {
        println("throwable caught " + e)
    }

    try {
        val n: String? = null
        println(n!!.length)
    } catch (e: Exception) {
        println("exception caught: " + (e is NullPointerException))
    }

    try {
        val n: String? = null
        println(n!!.length)
    } catch (e: NullPointerException) {
        println("npe caught")
    }

    try {
        val x: Any? = null
        println(x as String)
    } catch (e: Throwable) {
        println("cast null caught " + e)
    }

    try {
        throw NullPointerException("explicit")
    } catch (e: NullPointerException) {
        println(e.message)
    }

    fun f(s: String?) = s!!.length

    try {
        println(f(null))
    } catch (e: NullPointerException) {
        println("npe fn caught")
    }

    println("end")
}
