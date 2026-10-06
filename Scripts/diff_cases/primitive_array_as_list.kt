// KUU-1281: primitive asList views preserve element types and live backing storage.
fun main() {
    println(booleanArrayOf(true).asList())
    println(charArrayOf('a').asList())
    println(doubleArrayOf(1.5).asList())
    println(floatArrayOf(1.5f).asList())

    val booleans = BooleanArray(2)
    booleans[0] = true
    val booleanView = booleans.asList()
    val booleanIterator = booleanView.iterator()
    booleans[0] = false
    booleans[1] = true
    println(booleanView)
    println(booleanIterator.next())
    println(booleanView.subList(1, 2))
    println(booleanView.asReversed())
    println(booleanView == listOf(false, true))
    val booleanValue: Any = booleanView[1]
    println(booleanValue is Boolean)

    val chars = CharArray(2)
    chars[0] = 'a'
    chars[1] = 'b'
    val charView = chars.asList()
    chars[0] = 'z'
    println(charView)
    println(charView.iterator().next())
    println(charView.subList(0, 1))
    println(charView.asReversed())
    println(charView == listOf('z', 'b'))
    val charValue: Any = charView[0]
    println(charValue is Char)

    val doubles = DoubleArray(2)
    doubles[0] = 1.5
    val doubleView = doubles.asList()
    doubles[1] = -0.0
    println(doubleView)
    println(doubleView.iterator().next())
    println(doubleView.subList(1, 2))
    println(doubleView.asReversed())
    println(doubleView == listOf(1.5, -0.0))
    val doubleValue: Any = doubleView[1]
    println(doubleValue is Double)

    val floats = FloatArray(2)
    floats[0] = 1.5f
    val floatView = floats.asList()
    floats[1] = -0.0f
    println(floatView)
    println(floatView.iterator().next())
    println(floatView.subList(1, 2))
    println(floatView.asReversed())
    println(floatView == listOf(1.5f, -0.0f))
    val floatValue: Any = floatView[1]
    println(floatValue is Float)

    println(BooleanArray(0).asList())
    println(CharArray(0).asList())
    println(DoubleArray(0).asList())
    println(FloatArray(0).asList())
}
