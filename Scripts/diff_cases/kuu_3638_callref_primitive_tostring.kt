fun main() {
    // Primitive `Type::toString` callable references invoked as function
    // values: the unbound receiver argument crosses the erased `Any`
    // member-bridge boundary and must arrive boxed (KUU-3638).
    val boolToString: (Boolean) -> String = Boolean::toString
    println(boolToString(true))
    println(boolToString(false))
    val charToString: (Char) -> String = Char::toString
    println(charToString('A'))
    println(charToString('0'))
    val intToString: (Int) -> String = Int::toString
    println(intToString(42))
    val longToString: (Long) -> String = Long::toString
    println(longToString(Long.MIN_VALUE))
    val floatToString: (Float) -> String = Float::toString
    println(floatToString(1.5f))
    val doubleToString: (Double) -> String = Double::toString
    println(doubleToString(-0.0))
    println(doubleToString(3.25))
    val byteToString: (Byte) -> String = Byte::toString
    println(byteToString(7))
    val shortToString: (Short) -> String = Short::toString
    println(shortToString(300))
    val ulongToString: (ULong) -> String = ULong::toString
    println(ulongToString(ULong.MAX_VALUE))
    // Bound receiver keeps the same box through the member bridge.
    val b = true
    val boundRef: () -> String = b::toString
    println(boundRef())
    // Direct-call control: already used the typed bridge path.
    println(true.toString())
    // `Any::toString` invoked with primitive arguments.
    val anyToString: (Any) -> String = Any::toString
    println(anyToString(true))
    println(anyToString(42))
    println(anyToString("hi"))
}
