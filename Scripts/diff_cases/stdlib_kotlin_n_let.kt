fun main() {
    println(41.let { it + 1 })
    println(("kotlin" as String?)?.let { it.length })
    println((null as String?)?.let { it.length })
    println("hello".let { value -> value + "!" })
}
