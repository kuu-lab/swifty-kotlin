fun main() {
    var n = 5
    for (i in 0..n) { n--; print(i) }
    println(" n=$n")
    var m = 3
    for (i in 0 until m) { m++; print(i) }
    println(" m=$m")
    var hi = 9
    for (i in hi downTo 7) { hi = 0; print(i) }
    println(" hi=$hi")
    var k = 2
    for (i in k..k + 2) { k = 100; print(i) }
    println(" k=$k")
}
