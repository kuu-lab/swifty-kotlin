class M(val name: String) {
    operator fun plus(modules: List<M>) = listOf(this) + modules
}

operator fun List<M>.plus(module: M): List<M> = this + listOf(module)

fun main() {
    val ms = listOf(M("a"))
    println((ms + M("b")).map { it.name })
    println((ms + listOf(M("c"), M("d"))).map { it.name })
    println((M("x") + listOf(M("y"))).map { it.name })
}
