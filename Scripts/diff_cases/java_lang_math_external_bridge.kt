fun main() {
    println(Math.scalb(1.5, 3) == 12.0)
    println(Math.scalb(1.5f, 3) == 12.0f)
    println(Math.scalb(-0.0, 40).toRawBits() == (-0.0).toRawBits())
    println(Math.scalb(1.0, -1074) == Double.MIN_VALUE)
    println(Math.fma(2.0, 3.0, 4.0) == 10.0)
    println(Math.fma(2.0f, 3.0f, 4.0f) == 10.0f)
    println(Math.fma(1.0e16, 1.0000000000000002, -1.0e16) == 2.220446049250313)
    println(Math.fma(Double.POSITIVE_INFINITY, 0.0, 1.0).isNaN())
    val list = ArrayList<Int>()
    list.add(12)
    println(list.size == 1 && list[0] == 12)
}
