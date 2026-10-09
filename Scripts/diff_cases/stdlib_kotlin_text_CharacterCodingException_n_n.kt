// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_text_CharacterCodingException_n_n.expected.txt

import kotlin.text.CharacterCodingException

fun main() {
    val noArg = CharacterCodingException()
    val messageOnly = CharacterCodingException("bad input")
    val nullableMessage: String? = null
    val explicitNull = CharacterCodingException(nullableMessage)

    println(noArg.message ?: "null")
    println(messageOnly.message ?: "null")
    println(explicitNull.message ?: "null")
    println(noArg.cause?.message ?: "null")
    println(messageOnly.cause?.message ?: "null")
    println(explicitNull.cause?.message ?: "null")

    val caughtCharacter = try {
        throw messageOnly
    } catch (e: CharacterCodingException) {
        "character:${e.message ?: "null"}"
    } catch (e: Exception) {
        "exception:${e.message ?: "null"}"
    }
    println(caughtCharacter)

    val caughtSibling = try {
        throw Exception("other")
    } catch (e: CharacterCodingException) {
        "wrong"
    } catch (e: Exception) {
        "exception:${e.message ?: "null"}"
    }
    println(caughtSibling)
}
