fun selG(o: TOp, i: Int): Int = o[i]
fun selP(o: TOp, x: Int): Int = o + x
fun selM(o: TOp, x: Int): Int = o - x
fun selU(o: TOp): Int = -o
fun selS(o: TOp, i: Int, v: Int) { o[i] = v }
fun selI(o: TOp): Int = o()
fun selLt(o: TOp, x: TOp): Boolean = o < x
fun selIn(o: TOp, i: Int): Boolean = i in o
fun selCA(o: TOp, i: Int) { o[i] += 5 }

class TOp(val x: Int) {
    operator fun get(i: Int) = i
    operator fun set(i: Int, v: Int) { }
    operator fun plus(v: Int) = v
    operator fun minus(v: Int) = v
    operator fun unaryMinus() = -x
    operator fun compareTo(o: TOp) = x - o.x
    operator fun contains(i: Int) = i == x
    operator fun invoke() = 7
}

fun main() {
    val t = TOp(3)
    println(selG(t, 1))
    println(selP(t, 10))
    println(selM(t, 1))
    println(selU(t))
    selS(t, 0, 9)
    println(selI(t))
    println(selLt(t, TOp(1)))
    println(selIn(t, 3))
    selCA(t, 0)
    println("done")
}
