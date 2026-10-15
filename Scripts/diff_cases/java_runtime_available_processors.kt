fun box() : String {
    val processors = Runtime.getRuntime()!!.availableProcessors()
    var threadNum = 1
    while(threadNum <= 1024) {
        if(threadNum < 2 * processors)
            threadNum += 1
        else
            threadNum *= 2
    }
    return "OK"
}

private fun minimalRepro(): Boolean = Runtime.getRuntime()!!.availableProcessors() >= 1

fun main() {
    val runtime = Runtime.getRuntime()!!
    val preservesExistingApis = runtime === Runtime.getRuntime()
        && runtime.totalMemory() > 0L
        && runtime.freeMemory() >= 0L
        && runtime.maxMemory() >= runtime.totalMemory()
    println(if (box() == "OK" && minimalRepro() && preservesExistingApis) "OK" else "FAIL")
}
