// Proposed candidate-only regression; not compiled or executed.
var initializationCount = 0
fun boot(): Int {
    initializationCount += 1
    println("init")
    return 42
}
val initialized = boot()
fun main(args: Array<String>) {
    val label = if (args.size > 0) args[0] else "empty"
    println(label + ":" + initializationCount)
    if (label == "first") {
        main(arrayOf("again"))
        println("after:" + initializationCount)
    }
}
