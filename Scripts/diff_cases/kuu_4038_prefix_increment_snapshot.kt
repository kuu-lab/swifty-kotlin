// KUU-4038: prefix `++x` / `--x` must yield the value at that point in
// evaluation, not an alias of the variable's storage cell. Before the fix
// the desugared block's trailing bare `x` read returned x's storage
// register, so `val p = ++x` and `++x + ++x` observed later writes.
class CounterBox { var value = 5 }

var topLevel = 5

fun main() {
    var a = 5
    val p = ++a
    a = 100
    println(p)                  // 6

    var h = 5
    val t1 = ++h
    val t2 = h++
    println("$t1 $t2")          // 6 6

    var k = 5
    println(++k + ++k)          // 13 (6+7)

    var i = 5
    println(++i + i++)          // 12 (6+6)

    var m = 5
    println(--m - m--)          // 0 (4-4)

    var d = 5
    val q = --d
    d = 100
    println(q)                  // 4

    // Member property with an explicit receiver already produced a getter
    // call temporary; keep it pinned alongside the fixed local-var case.
    val box = CounterBox()
    val bp = ++box.value
    box.value = 100
    println("$bp ${box.value}") // 6 100

    val arr = intArrayOf(5)
    val ap = ++arr[0]
    arr[0] = 100
    println("$ap ${arr[0]}")    // 6 100

    val tp = ++topLevel
    topLevel = 100
    println("$tp $topLevel")    // 6 100
}
