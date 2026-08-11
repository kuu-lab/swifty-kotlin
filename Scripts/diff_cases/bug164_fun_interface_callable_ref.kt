// BUG-164 minimal repro: callable reference passed to fun interface parameter.

fun interface Transformer {
    fun transform(s: String): Int
}

fun transformImpl(s: String): Int = s.length

fun myApply(t: Transformer): Int = t.transform("hello")

fun main() {
    println(myApply(::transformImpl))
}
