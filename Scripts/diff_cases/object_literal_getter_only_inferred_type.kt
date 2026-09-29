interface Counter { fun inc(): Int; val name: String }
class Named : Counter { var v = 0; override fun inc() = ++v; override val name get() = "n$v" }
fun main() {
    val multi = object : Counter { var v = 0; override fun inc() = ++v; override val name get() = "m$v" }
    multi.inc(); multi.inc()
    println(multi.name)
    println(multi.v)
    val c: Counter = multi; println(c.name)
    val n = Named(); n.inc(); n.inc(); println(n.name)
    val plain = object { var v = 0; val name get() = "p$v" }
    plain.v = 3; println(plain.name)
    val acc = object {
        var raw = 1
        var x get() = raw * 10
            set(value) { raw = value }
        val y
            get() = raw + 1
    }
    acc.x = 5
    println(acc.x)
    println(acc.y)
}
