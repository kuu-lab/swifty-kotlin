fun main() {
    val intValues = intArrayOf(1, 2, 3, 4, 5)
    val (int1, int2, int3, int4, int5) = intValues
    println("$int1:$int2:$int3:$int4:$int5")
    println("${intValues.component1()}:${intValues.component2()}:${intValues.component3()}:${intValues.component4()}:${intValues.component5()}")
    try {
        IntArray(0).component1()
        println("missing exception")
    } catch (e: IndexOutOfBoundsException) {
        println("int bounds")
    }
    try {
        IntArray(4).component5()
        println("missing exception")
    } catch (e: IndexOutOfBoundsException) {
        println("int fifth bounds")
    }
    val longValues = longArrayOf(10000000000L, -2L, 3L, 4L, 5L)
    val (long1, long2, long3, long4, long5) = longValues
    println("$long1:$long2:$long3:$long4:$long5")
    println("${longValues.component1()}:${longValues.component2()}:${longValues.component3()}:${longValues.component4()}:${longValues.component5()}")
    try {
        LongArray(0).component1()
        println("missing exception")
    } catch (e: IndexOutOfBoundsException) {
        println("long bounds")
    }
    try {
        LongArray(4).component5()
        println("missing exception")
    } catch (e: IndexOutOfBoundsException) {
        println("long fifth bounds")
    }
    val shortValues = shortArrayOf(1, -2, 3, 4, 5)
    val (short1, short2, short3, short4, short5) = shortValues
    println("$short1:$short2:$short3:$short4:$short5")
    println("${shortValues.component1()}:${shortValues.component2()}:${shortValues.component3()}:${shortValues.component4()}:${shortValues.component5()}")
    try {
        ShortArray(0).component1()
        println("missing exception")
    } catch (e: IndexOutOfBoundsException) {
        println("short bounds")
    }
    try {
        ShortArray(4).component5()
        println("missing exception")
    } catch (e: IndexOutOfBoundsException) {
        println("short fifth bounds")
    }
    val byteValues = byteArrayOf(1, -2, 3, 4, 5)
    val (byte1, byte2, byte3, byte4, byte5) = byteValues
    println("$byte1:$byte2:$byte3:$byte4:$byte5")
    println("${byteValues.component1()}:${byteValues.component2()}:${byteValues.component3()}:${byteValues.component4()}:${byteValues.component5()}")
    try {
        ByteArray(0).component1()
        println("missing exception")
    } catch (e: IndexOutOfBoundsException) {
        println("byte bounds")
    }
    try {
        ByteArray(4).component5()
        println("missing exception")
    } catch (e: IndexOutOfBoundsException) {
        println("byte fifth bounds")
    }
    val charValues = charArrayOf('a', 'b', 'c', 'd', 'e')
    val (char1, char2, char3, char4, char5) = charValues
    println("$char1:$char2:$char3:$char4:$char5")
    println("${charValues.component1()}:${charValues.component2()}:${charValues.component3()}:${charValues.component4()}:${charValues.component5()}")
    try {
        CharArray(0).component1()
        println("missing exception")
    } catch (e: IndexOutOfBoundsException) {
        println("char bounds")
    }
    try {
        CharArray(4).component5()
        println("missing exception")
    } catch (e: IndexOutOfBoundsException) {
        println("char fifth bounds")
    }
    val booleanValues = booleanArrayOf(true, false, true, false, true)
    val (boolean1, boolean2, boolean3, boolean4, boolean5) = booleanValues
    println("$boolean1:$boolean2:$boolean3:$boolean4:$boolean5")
    println("${booleanValues.component1()}:${booleanValues.component2()}:${booleanValues.component3()}:${booleanValues.component4()}:${booleanValues.component5()}")
    try {
        BooleanArray(0).component1()
        println("missing exception")
    } catch (e: IndexOutOfBoundsException) {
        println("boolean bounds")
    }
    try {
        BooleanArray(4).component5()
        println("missing exception")
    } catch (e: IndexOutOfBoundsException) {
        println("boolean fifth bounds")
    }
    val floatValues = floatArrayOf(1.5f, -2.5f, 3.0f, 4.0f, 5.0f)
    val (float1, float2, float3, float4, float5) = floatValues
    println("$float1:$float2:$float3:$float4:$float5")
    println("${floatValues.component1()}:${floatValues.component2()}:${floatValues.component3()}:${floatValues.component4()}:${floatValues.component5()}")
    try {
        FloatArray(0).component1()
        println("missing exception")
    } catch (e: IndexOutOfBoundsException) {
        println("float bounds")
    }
    try {
        FloatArray(4).component5()
        println("missing exception")
    } catch (e: IndexOutOfBoundsException) {
        println("float fifth bounds")
    }
    val doubleValues = doubleArrayOf(1.5, -2.5, 3.0, 4.0, 5.0)
    val (double1, double2, double3, double4, double5) = doubleValues
    println("$double1:$double2:$double3:$double4:$double5")
    println("${doubleValues.component1()}:${doubleValues.component2()}:${doubleValues.component3()}:${doubleValues.component4()}:${doubleValues.component5()}")
    try {
        DoubleArray(0).component1()
        println("missing exception")
    } catch (e: IndexOutOfBoundsException) {
        println("double bounds")
    }
    try {
        DoubleArray(4).component5()
        println("missing exception")
    } catch (e: IndexOutOfBoundsException) {
        println("double fifth bounds")
    }
    val (only, _, _, _, _) = intArrayOf(9)
    println(only)
    try {
        val (first, second) = intArrayOf(1)
        println("$first:$second")
    } catch (e: IndexOutOfBoundsException) {
        println("destructure bounds")
    }
}
