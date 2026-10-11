fun main() {
    lateinit var local: String
    println("declared")
    try { println(local) } catch (e: UninitializedPropertyAccessException) {
        println("read:" + e.message)
    }
    local = "ready"
    println("initialized:" + local)

    lateinit var captured: String
    val reader = { captured }
    println("lambda-created")
    try { println(reader()) } catch (e: UninitializedPropertyAccessException) {
        println("lambda:" + e.message)
    }
    captured = "first"
    println("lambda-after:" + reader())
    captured = "second"
    println("lambda-reassigned:" + reader())

    lateinit var assigned: String
    val writer = { assigned = "written" }
    writer()
    println("lambda-write:" + assigned)

    lateinit var callback: () -> String
    val invokeReader = { callback() }
    try { println(invokeReader()) } catch (e: UninitializedPropertyAccessException) {
        println("callable:" + e.message)
    }
    callback = { "called" }
    println("callable-after:" + invokeReader())
}
