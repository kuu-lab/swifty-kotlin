// KUU-1237: private member extensions retain both receivers and infer String results.
class Host {
    private fun String.helper(): String = this
    fun use(s: String) = s.helper()
    fun use2() = "x".helper()
}

class Container {
    private class Scanner(private val prefix: String) {
        private fun String.toSingleLineString(): String = prefix + this
        fun scan(s: String) = s.toSingleLineString()
        fun scanLiteral() = "line".toSingleLineString()
    }

    fun run() {
        val scanner = Scanner("scan:")
        println(scanner.scan("input"))
        println(scanner.scanLiteral())
    }
}

fun main() {
    val host = Host()
    println(host.use("hello"))
    println(host.use2())
    Container().run()
}
