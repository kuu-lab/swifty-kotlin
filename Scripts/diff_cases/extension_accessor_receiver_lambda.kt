class Authority(val host: String, val port: Int) {
    fun hostName(): String = host
}

val Authority.authority: String
    get() = buildString {
        append(host)
        append(":")
        append(port.toString())
    }

fun Authority.render(): String = buildString {
    append(host)
    append(":")
    append(port.toString())
}

val Authority.nested: String
    get() = buildString {
        append(buildString { append(host); append(":"); append(port.toString()) })
    }

val Authority.labeled: String
    get() = buildString { append(this@labeled.host) }

var Authority.copy: String
    get() = authority
    set(value) {
        println(buildString { append(hostName()); append(":"); append(value) })
    }

class HostScope(val host: String)
fun Authority.shadow(): String = HostScope("inner").run { host }

fun main() {
    val value = Authority("example.com", 8080)
    println(value.authority)
    println(value.render())
    println(value.nested)
    println(value.labeled)
    value.copy = "saved"
    println(value.shadow())
}
