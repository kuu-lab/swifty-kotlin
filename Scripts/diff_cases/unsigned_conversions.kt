fun main() {
    // UInt numeric conversions: toChar() does not exist on UInt in Kotlin
    // (verified against kotlinc and the stdlib source); the correct spelling
    // for narrowing to a code unit goes through toInt().toChar().
    println(UInt.MAX_VALUE.toInt())
    println(UInt.MAX_VALUE.toDouble())
    println(UInt.MAX_VALUE.toLong())
    println(UInt.MAX_VALUE.toInt().toChar().code)
}
