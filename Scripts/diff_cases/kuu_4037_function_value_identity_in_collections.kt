// KUU-4037: a function value stored into an array-backed generic collection
// used to be re-wrapped in a fresh function box on every erased-storage
// crossing, minting a new object each time — so `===`, `contains`, `indexOf`,
// `remove`, `setOf` dedup and `Map` key lookups all silently failed. The
// container slot now keeps the already-boxed value's own object, matching
// kotlinc's single-object semantics.

fun main() {
    val f: (Int) -> Unit = { }
    println(listOf(f)[0] === f)
    println(arrayOf(f)[0] === f)
    println(f in listOf(f))
    println(f in setOf(f))

    val m = mutableMapOf<(Int) -> Unit, Int>()
    m[f] = 1
    println(m[f])

    println((f to 1).first === f)
    val a: Any? = f
    println(a === f)

    val ml = mutableListOf(f)
    println(ml[0] !== f)
    println(ml.indexOf(f))
    println(ml.remove(f))

    // Function values whose parameters/return are non-Any (a raw-value ABI)
    // must keep identity too: the box already serves the declared element
    // signature it is read back as.
    val g1: (Int) -> Int = { it + 1 }
    val g2: (Int) -> Int = { it + 2 }
    println(listOf(g1)[0] === g1)
    println(listOf(g1)[0](9))
    println(listOf(g1, g1, g2).map { it(9) })
    println(setOf(g1, g1, g2).size)

    val m2 = mutableMapOf<(Int) -> Int, String>()
    m2[g1] = "a"
    m2[g2] = "b"
    println(m2[g1])
    println(m2[g2])

    // Arity-2 and receiver lambdas round-trip through the same erased slots.
    val two: (Int, Int) -> Int = { x, y -> x + y }
    println(listOf(two)[0] === two)
    println(listOf(two)[0](3, 4))
    val ext: String.() -> Int = { length }
    println(listOf(ext)[0] === ext)
    println(listOf(ext)[0]("abc"))

    // An explicitly widened element type still invokes through the declared
    // signature — the value itself stays the same object.
    val cov: () -> Int = { 42 }
    val covList: List<() -> Any> = listOf(cov)
    println(covList[0]())
    println(covList[0] === cov)
}
