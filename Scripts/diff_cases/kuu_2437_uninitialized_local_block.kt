fun box(): String {
    val fps: Double = 1.toDouble()
    var mspf: Long
    {
        if (fps.toInt() == 0)
            mspf = 0
        else
            mspf = (((1000.0 / fps)).toLong())
    }
    return "OK"
}

fun minimal(): String {
    var value: Int
    {}
    return "OK"
}

fun initializedControl(): String {
    var value: Int = 0
    {}
    return "OK"
}

fun directAssignmentControl(): String {
    var value: Int
    value = 1
    return if (value == 1) "OK" else "FAIL"
}

fun run(block: () -> Unit) {
    block()
}

fun trailingLambdaControl(): String {
    var value = "OK"
    run()
        { value = "OK" }
    return value
}

fun main() {
    println(box())
    println(minimal())
    println(initializedControl())
    println(directAssignmentControl())
    println(trailingLambdaControl())
}
