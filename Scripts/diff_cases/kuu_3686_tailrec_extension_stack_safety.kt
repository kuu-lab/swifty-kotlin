// KUU-3686: generic extension-function tail calls with a function argument
// must remain stack-safe beyond the depth that previously overflowed.
tailrec fun <T, A> Iterator<T>.foldl(acc: A, f: (e: T, acc: A) -> A): A =
    if (!hasNext()) acc else foldl(f(next(), acc), f)

fun main() {
    println((1..200_000).iterator().foldl(0L) { e, acc -> acc + e })
}
