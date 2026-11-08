fun main() {
    fun <T> f(t: T): T where T : Comparable<T> = t
    fun <T> g(t: T): T
        where T : Comparable<T> {
        return t
    }
    fun <T> h(t: T) where T : Comparable<T> = t
    println(f(1))
    println(g("x"))
    println(h(2))
}
