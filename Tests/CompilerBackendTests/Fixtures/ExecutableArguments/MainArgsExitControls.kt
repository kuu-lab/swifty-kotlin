import kotlin.system.exitProcess

fun main(args: Array<String>) {
    if (args[0] == "throw") {
        println("before:" + args[1])
        throw IllegalStateException("top-level")
    }
    println("before-exit")
    exitProcess(23)
}
