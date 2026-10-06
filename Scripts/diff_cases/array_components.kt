@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    run {
        val values: Array<String?> = arrayOf<String?>("a", null, "c", "d", "e")
        val (a, b, c, d, e) = values
        println(a)
        println(values.component1())
        println(b)
        println(values.component2())
        println(c)
        println(values.component3())
        println(d)
        println(values.component4())
        println(e)
        println(values.component5())
        val (_, _, _, _, last) = values
        println(last)
        try {
            emptyArray<String?>().component1()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
        try {
            arrayOf<String?>("a", "b", "c", "d").component5()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
    }
    run {
        val values: IntArray = intArrayOf(1,2,3,4,5)
        val (a, b, c, d, e) = values
        println(a)
        println(values.component1())
        println(b)
        println(values.component2())
        println(c)
        println(values.component3())
        println(d)
        println(values.component4())
        println(e)
        println(values.component5())
        val (_, _, _, _, last) = values
        println(last)
        try {
            IntArray(0).component1()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
        try {
            IntArray(4).component5()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
    }
    run {
        val values: LongArray = longArrayOf(1L,2L,3L,4L,5L)
        val (a, b, c, d, e) = values
        println(a)
        println(values.component1())
        println(b)
        println(values.component2())
        println(c)
        println(values.component3())
        println(d)
        println(values.component4())
        println(e)
        println(values.component5())
        val (_, _, _, _, last) = values
        println(last)
        try {
            LongArray(0).component1()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
        try {
            LongArray(4).component5()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
    }
    run {
        val values: ShortArray = shortArrayOf(1,2,3,4,5)
        val (a, b, c, d, e) = values
        println(a)
        println(values.component1())
        println(b)
        println(values.component2())
        println(c)
        println(values.component3())
        println(d)
        println(values.component4())
        println(e)
        println(values.component5())
        val (_, _, _, _, last) = values
        println(last)
        try {
            ShortArray(0).component1()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
        try {
            ShortArray(4).component5()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
    }
    run {
        val values: ByteArray = byteArrayOf(1,2,3,4,5)
        val (a, b, c, d, e) = values
        println(a)
        println(values.component1())
        println(b)
        println(values.component2())
        println(c)
        println(values.component3())
        println(d)
        println(values.component4())
        println(e)
        println(values.component5())
        val (_, _, _, _, last) = values
        println(last)
        try {
            ByteArray(0).component1()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
        try {
            ByteArray(4).component5()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
    }
    run {
        val values: CharArray = charArrayOf('a','b','c','d','e')
        val (a, b, c, d, e) = values
        println(a)
        println(values.component1())
        println(b)
        println(values.component2())
        println(c)
        println(values.component3())
        println(d)
        println(values.component4())
        println(e)
        println(values.component5())
        val (_, _, _, _, last) = values
        println(last)
        try {
            CharArray(0).component1()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
        try {
            CharArray(4).component5()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
    }
    run {
        val values: BooleanArray = booleanArrayOf(true,false,true,false,true)
        val (a, b, c, d, e) = values
        println(a)
        println(values.component1())
        println(b)
        println(values.component2())
        println(c)
        println(values.component3())
        println(d)
        println(values.component4())
        println(e)
        println(values.component5())
        val (_, _, _, _, last) = values
        println(last)
        try {
            BooleanArray(0).component1()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
        try {
            BooleanArray(4).component5()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
    }
    run {
        val values: FloatArray = floatArrayOf(1f,2f,3f,4f,5f)
        val (a, b, c, d, e) = values
        println(a)
        println(values.component1())
        println(b)
        println(values.component2())
        println(c)
        println(values.component3())
        println(d)
        println(values.component4())
        println(e)
        println(values.component5())
        val (_, _, _, _, last) = values
        println(last)
        try {
            FloatArray(0).component1()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
        try {
            FloatArray(4).component5()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
    }
    run {
        val values: DoubleArray = doubleArrayOf(1.0,2.0,3.0,4.0,5.0)
        val (a, b, c, d, e) = values
        println(a)
        println(values.component1())
        println(b)
        println(values.component2())
        println(c)
        println(values.component3())
        println(d)
        println(values.component4())
        println(e)
        println(values.component5())
        val (_, _, _, _, last) = values
        println(last)
        try {
            DoubleArray(0).component1()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
        try {
            DoubleArray(4).component5()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
    }
    run {
        val values: UIntArray = uintArrayOf(1u,2u,3u,4u,UInt.MAX_VALUE)
        val (a, b, c, d, e) = values
        println(a)
        println(values.component1())
        println(b)
        println(values.component2())
        println(c)
        println(values.component3())
        println(d)
        println(values.component4())
        println(e)
        println(values.component5())
        val (_, _, _, _, last) = values
        println(last)
        try {
            UIntArray(0).component1()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
        try {
            UIntArray(4).component5()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
    }
    run {
        val values: ULongArray = ulongArrayOf(1uL,2uL,3uL,4uL,ULong.MAX_VALUE)
        val (a, b, c, d, e) = values
        println(a)
        println(values.component1())
        println(b)
        println(values.component2())
        println(c)
        println(values.component3())
        println(d)
        println(values.component4())
        println(e)
        println(values.component5())
        val (_, _, _, _, last) = values
        println(last)
        try {
            ULongArray(0).component1()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
        try {
            ULongArray(4).component5()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
    }
    run {
        val values: UShortArray = ushortArrayOf(1u,2u,3u,4u,65535u)
        val (a, b, c, d, e) = values
        println(a)
        println(values.component1())
        println(b)
        println(values.component2())
        println(c)
        println(values.component3())
        println(d)
        println(values.component4())
        println(e)
        println(values.component5())
        val (_, _, _, _, last) = values
        println(last)
        try {
            UShortArray(0).component1()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
        try {
            UShortArray(4).component5()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
    }
    run {
        val values: UByteArray = ubyteArrayOf(1u,2u,3u,4u,255u)
        val (a, b, c, d, e) = values
        println(a)
        println(values.component1())
        println(b)
        println(values.component2())
        println(c)
        println(values.component3())
        println(d)
        println(values.component4())
        println(e)
        println(values.component5())
        val (_, _, _, _, last) = values
        println(last)
        try {
            UByteArray(0).component1()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
        try {
            UByteArray(4).component5()
            println("missing exception")
        } catch (e: IndexOutOfBoundsException) {
            println("bounds")
        }
    }
}
