sealed class Result {
    data class Ok(val v: Int) : Result()
    data class Err(val msg: String) : Result()
}
fun Result.text() = when (this) { is Result.Ok -> "ok$v"; is Result.Err -> "err:$msg" }

sealed class Top
class A1(val a: Int) : Top()
class B1(val b: String) : Top()
fun Top.t() = when (this) { is A1 -> "a$a"; is B1 -> "b$b" }

fun main() {
    val rs: List<Result> = listOf(Result.Ok(1), Result.Err("bad"))
    println(rs.map { it.text() })
    println(listOf<Top>(A1(1), B1("x")).map { it.t() })
}
