package golden.sema

fun stringBuilderAppendMissing(): StringBuilder {
    val builder = StringBuilder()
    val anyValue: Any? = null
    val chars = charArrayOf('a', 'b', 'c')
    val byteValue: Byte = 1
    val shortValue: Short = 2
    builder.append(anyValue)
    builder.append(byteValue)
    builder.append(chars)
    builder.append(shortValue)
    builder.appendRange(chars, 0, 2)
    return builder
}

fun stringBuilderIndexMissing(): Int {
    val builder = StringBuilder("a😀ba😀b")
    return builder.indexOf("😀") + builder.indexOf("😀", 4) +
        builder.lastIndexOf("b") + builder.lastIndexOf("b", 4)
}

fun stringBuilderInsertMissing(): StringBuilder {
    val chars = charArrayOf('x', 'y')
    val sequence: CharSequence? = null
    val builder = StringBuilder("ab")
    builder.insert(1, 1.toByte())
    builder.insert(1, chars)
    builder.insert(1, sequence)
    builder.insert(1, 2.toShort())
    builder.insertRange(1, chars, 0, 2)
    return builder
}

fun stringBuilderSetLengthMissing(): Unit {
    StringBuilder("abc").setLength(1)
}

fun stringBuilderSubstringMissing(): String {
    val builder = StringBuilder("a😀b")
    return builder.substring(1) + builder.substring(1, 3)
}

fun stringBuilderToCharArrayMissing(): CharArray {
    val destination = CharArray(4)
    StringBuilder("wxyz").toCharArray(destination, 1, 1, 3)
    return destination
}
