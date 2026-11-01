// KUU-4120: a `var` captured by a local/anonymous function or object literal
// created inside a `while` body must share one cell with the loop condition.
// Boxing it lazily at the capture site re-created the cell every iteration
// and left the condition reading a stale unboxed register -> infinite loop.
fun main() {
    // Anonymous function created in the loop body captures `j`; `j++` must
    // reach the same storage `j < 3` reads.
    var j = 0
    while (j < 3) {
        println((fun(): Int = j)())
        j++
    }
    println("done " + j)

    // The same capture through a named local function.
    var k = 0
    while (k < 3) {
        fun read(): Int = k
        println(read())
        k++
    }
    println("done " + k)

    // Writes performed inside the anonymous function itself.
    var m = 0
    while (m < 3) {
        val bump = fun(): Int { m += 1; return m }
        println(bump())
    }
    println("done " + m)

    // `var` declared without an initializer, first assigned before the loop.
    var n: Int
    n = 0
    while (n < 2) {
        val read = fun(): Int = n
        println(read())
        n++
    }
    println("done " + n)

    // Object-literal member capturing the loop variable.
    var p = 0
    while (p < 2) {
        val box = object {
            fun read(): Int = p
        }
        println(box.read())
        p++
    }
    println("done " + p)

    // do-while: the condition is lowered after the body but the capture cell
    // must still be the single one created at `var q`.
    var q = 0
    do {
        val read = fun(): Int = q
        println(read())
        q++
    } while (q < 2)
    println("done " + q)
}
