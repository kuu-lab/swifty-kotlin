class C {
    init { log += "i" }
    fun f() { log += "f" }
    companion object {
        val log = mutableListOf<String>()
        val tags = mutableSetOf<String>()
        val counts = mutableMapOf<String, Int>()
        init {
            log += "ci"
            tags += "ready"
            counts += "init" to 1
        }
        fun g() { log += "g" }
    }
}

class Named {
    init { values += 1 }
    fun add() { values += listOf(2, 3) }
    companion object Registry {
        val values = mutableListOf<Int>()
        init { values += 0 }
    }
}

class Accumulator {
    var value = 0
    operator fun plusAssign(x: Int) { value += x }
}

class Custom {
    init { total += 2 }
    fun add() { total += 3 }
    companion object {
        val total = Accumulator()
        init { total += 1 }
    }
}

class Shadow {
    val values = mutableListOf<Int>()
    companion object { val values = mutableListOf<String>() }
    fun add() { values += 7 }
    fun local(): List<Boolean> {
        val values = mutableListOf<Boolean>()
        values += true
        return values
    }
}

fun main() {
    C.log += "top"
    val c = C()
    c.f()
    C.g()
    C.Companion.log += listOf("last", "remove")
    C.log -= "remove"
    C.tags += "top"
    C.counts += "top" to 2
    println(C.log)
    println(C.tags)
    println(C.counts)

    val named = Named()
    named.add()
    Named.values += 4
    Named.Registry.values -= 2
    println(Named.values)

    val custom = Custom()
    custom.add()
    Custom.total += 4
    println(Custom.total.value)

    val shadow = Shadow()
    shadow.add()
    shadow.values += 8
    Shadow.values += "companion"
    println(shadow.values)
    println(shadow.local())
    println(Shadow.values)
}
