// Result.map/recover/recoverCatching keep the transform's type, and
// mapCatching resolves and captures exceptions thrown by the transform.
fun main() {
    val r: Result<Int> = runCatching { 2 }.map { it * 3 }
    println(r.getOrThrow() + 1)
    val rec: Result<Int> = runCatching<Int> { error("x") }.recover { 5 }
    println(rec.getOrThrow() * 2)
    val recc: Result<Int> = runCatching<Int> { error("x") }.recoverCatching { 9 }
    println(recc.getOrThrow() - 1)
    println(runCatching { 1 }.mapCatching { it / 0 }.exceptionOrNull()?.message)
    val ok: Result<String> = runCatching { 4 }.mapCatching { "v$it" }
    println(ok.getOrThrow().length)
    println(runCatching<Int> { error("orig") }.mapCatching { it + 1 }.exceptionOrNull()?.message)
}
