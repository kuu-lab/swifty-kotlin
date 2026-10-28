// Positive control for KUU-3667: indexed writes that satisfy the key type keep
// working — MutableMap.set resolves the map writes, while array and mutable
// list receivers keep the member/intrinsic set path.
fun main() {
    val m = HashMap<String, String>()
    m["a"] = "B"
    m["a"] += "C"
    val arr = intArrayOf(1, 2)
    arr[0] = 5
    var i = 1
    arr[i] = 6
    arr[0] += 2
    val l = mutableListOf(1)
    l[0] = 9
    println(m["a"])
    println(arr[0].toString() + arr[1].toString() + l[0].toString())
}
