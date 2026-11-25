// DIFF_JVM
@Target(AnnotationTarget.TYPE)
annotation class TypeAnno

@Target(AnnotationTarget.TYPE)
annotation class OtherAnno(val s: String = "")

// KUU-4611: an annotation before a parenthesized type annotates the group —
// `@Composable (() -> Unit)?` — instead of swallowing the parentheses as
// its argument list.
val nullableFn: @TypeAnno (() -> Unit)? = null
val parenthesized: @TypeAnno ((Int) -> Int) = { it }
val deepNested: @TypeAnno (((Int) -> Int)?) = null
val withArgs: @OtherAnno("a") (() -> Unit)? = null

fun takes(block: @TypeAnno (() -> Unit)? = null): @TypeAnno ((Int) -> Int)? {
    return null
}
fun <T> generic(arg: List<@TypeAnno (() -> Unit)?>) = arg

fun main() {
    takes { println("ok") }
    println("ok")
}
