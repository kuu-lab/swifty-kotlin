fun <A, T> ((A) -> T).toProvider(arg: () -> A): () -> T = { invoke(arg()) }

fun main() {
    val f: (Int) -> String = { "v$it" }
    println(f.toProvider { 3 }())
}
