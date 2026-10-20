class Strange {
    override fun equals(other: Any?): Boolean { println("equals"); return true }
}
fun main() {
    val strange = Strange()
    println(strange == null)
    println(null == strange)
    println(strange.equals(null))
}
