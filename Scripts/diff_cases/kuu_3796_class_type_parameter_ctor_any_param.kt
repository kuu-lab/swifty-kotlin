// KUU-3796: a constructor's class type parameters share symbols with the
// class's lexical type parameters. `P(key)` with `key: T` must infer `P<T>`
// from the expected type, not `P<Any?>` from the parameter's declared `Any?`.
class P<T>(val a: Any?) {
    fun f(key: T): P<T> {
        return P(key)
    }
}

class POM<K, V>(val firstKey: Any?, val lastKey: Any?, val payload: V) {
    fun put(key: K, value: V): POM<K, V> {
        return POM(key, key, value)
    }
}

fun main() {
    val p: P<String> = P("x")
    println(p.f("y").a)
    val m: POM<String, Int> = POM("a", "b", 1)
    println(m.put("k", 2).payload)
}
