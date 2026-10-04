package golden.sema

import kotlin.text.CharacterCodingException

fun fromNoArg(): CharacterCodingException = CharacterCodingException()

fun fromMessage(message: String?): CharacterCodingException = CharacterCodingException(message)

fun main() {
    val message: String? = "decode failed"
    println(fromNoArg().message ?: "null")
    println(fromMessage(message).message ?: "null")
    println(fromMessage(null).message ?: "null")
}
