interface O<T>
interface M<T> { fun asO(): O<T> }

fun <T, R> Iterable<O<T>>.zip(m: (List<T>) -> R): O<R>? = null

fun <T, R> Iterable<M<T>>.callableRef(m: (List<T>) -> R): O<R>? =
    map(M<T>::asO).zip(m)

fun <T, R> Iterable<M<T>>.lambdaChain(m: (List<T>) -> R): O<R>? =
    map { it.asO() }.zip(m)

fun <A, B> Iterable<O<A>>.localReceiver(m: (List<A>) -> B): O<B>? {
    val xs: List<O<A>> = listOf()
    val direct: O<B>? = xs.zip(m)
    val trailing: O<Int>? = xs.zip { list -> list.size }
    return direct
}

fun stdlibZipStillApplies() {
    val pairs = listOf(1, 2).zip(listOf("a", "b"))
    val transformed = listOf(1, 2).zip(listOf("a", "b")) { left, right -> "$left$right" }
    println(pairs)
    println(transformed)
}
