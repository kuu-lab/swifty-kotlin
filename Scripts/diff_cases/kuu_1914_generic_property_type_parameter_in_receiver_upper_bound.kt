data class Tuple<A>(val item: A)
val <T, A : T> Tuple<A>.components: List<T> get() = listOf(item)

data class Tuple1<T1>(val t1: T1)
val <T, T1 : T> Tuple1<T1>.components: List<T> get() = listOf(t1)

data class Tuple2<T1, T2>(val t1: T1, val t2: T2)
val <T, T1 : T, T2 : T> Tuple2<T1, T2>.components: List<T> get() = listOf(t1, t2)

fun main() {
    val reduced: List<Number> = Tuple(3).components
    val tuple1: List<Number> = Tuple1(3).components
    val tuple2: List<Number> = Tuple2(3, 4L).components
    println(reduced)
    println(tuple1)
    println(tuple2)
}
