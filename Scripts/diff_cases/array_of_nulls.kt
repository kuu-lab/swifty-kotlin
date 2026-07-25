fun main() {
    val arr = arrayOfNulls<String>(3)
    println(arr.size)
    println(arr[0])
    println(arr[1])
    arr[1] = "set"
    println(arr[1])

    val ints = arrayOfNulls<Int>(2)
    println(ints.size)
    println(ints[0])
    ints[0] = 42
    println(ints[0])

    val zero = arrayOfNulls<String>(0)
    println(zero.size)
}
