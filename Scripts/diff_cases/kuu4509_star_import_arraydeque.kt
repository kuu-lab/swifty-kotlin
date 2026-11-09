// KUU-4509: under `import java.util.*`, the star-imported classifier wins
// over the ordinary default import — `ArrayDeque` must bind
// `java.util.ArrayDeque` (whose `poll`/`peek`/`push`/`pop` members resolve),
// not `kotlin.collections.ArrayDeque`. Builtin types keep the opposite
// order: `kotlin.Function` still outranks `import java.util.function.*`
// (KUU-4424), so `Function<Int>` binds the arity-1 builtin.
import java.util.*
import java.util.function.*

fun main() {
    val d = ArrayDeque<Int>()
    d.addLast(1)
    d.addLast(2)
    println(d::class.qualifiedName)
    println(d.poll())
    println(d.peek())
    d.push(3)
    println(d.pop())

    val f: Function<Int> = { 42 }
    println(f is Function<Int>)
}
