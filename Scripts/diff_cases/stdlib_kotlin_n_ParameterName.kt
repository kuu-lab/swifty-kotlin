fun useParameterName(f: (@ParameterName("x") Int) -> Unit): Unit = f(0)

fun main() {
    useParameterName { }
    println("ok")
}
