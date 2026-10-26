fun main() {
    val exception = Exception("x")
    exception.stackTrace = emptyArray()
    println(exception.stackTrace.size)

    val assigned = arrayOf(StackTraceElement("example.Worker", "run", "Worker.kt", 27))
    exception.stackTrace = assigned
    assigned[0] = StackTraceElement("example.Mutated", "run", "Changed.kt", 99)
    val element = exception.stackTrace.first()
    println("${element.lineNumber}|${element.fileName}|${element.methodName}|${element.className}")
    val returned = exception.stackTrace
    returned[0] = StackTraceElement("example.Mutated", "run", "Changed.kt", 100)
    println(exception.stackTrace.first().lineNumber)
    println(exception.stackTraceToString().contains("example.Worker.run(Worker.kt:27)"))
}
