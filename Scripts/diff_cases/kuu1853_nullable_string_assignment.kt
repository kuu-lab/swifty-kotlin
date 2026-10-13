fun main() {
    var s: String? = null
    s = if (true) "x" else "y"
    println(s)

    var s2: String? = null
    s2 = "direct"
    println(s2)

    var number: Int? = null
    number = 1
    println(number)

    var flag: Boolean? = null
    flag = true
    println(flag)

    var initialized: String? = "initial"
    initialized = "updated"
    println(initialized)
}
