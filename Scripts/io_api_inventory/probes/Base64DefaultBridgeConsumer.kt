package f02base64consumer

import f02base64producer.decodeDefault as producerDecodeDefault
import f02base64producer.decodeIntoByteArrayDefault as producerDecodeIntoByteArrayDefault
import f02base64producer.decodeToByteStringArrayDefault as producerDecodeToByteStringArrayDefault
import f02base64producer.decodeToByteStringCharsDefault as producerDecodeToByteStringCharsDefault
import f02base64producer.decodeToByteStringDefault as producerDecodeToByteStringDefault
import kotlinx.io.bytestring.ByteString
import kotlinx.io.bytestring.decode
import kotlinx.io.bytestring.decodeIntoByteArray
import kotlinx.io.bytestring.decodeToByteString
import kotlinx.io.bytestring.decodeToString
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

private const val DECODE_ROW = "jvm-06eee316b84478d8"
private const val CHAR_SEQUENCE_ROW = "jvm-0a7391fd7c844ff7"
private const val BYTE_ARRAY_ROW = "jvm-1ba14d2113458d26"
private const val INTO_ARRAY_ROW = "jvm-c376d0d1321523df"
private const val BYTE_STRING_ROW = "jvm-ebe766fdf289f961"

private val encoded = "SGVsbG8="
private val encodedChars: CharSequence = encoded
private val encodedArray = encoded.encodeToByteArray()
private val encodedByteString = ByteString(encodedArray)

private fun expect(rowId: String, call: String, actual: String, expected: String) {
    if (actual != expected) {
        throw IllegalStateException("$rowId $call expected <$expected>, got <$actual>")
    }
    println("PASS:$rowId:$call:$actual")
}

private fun expectIndexOutOfBounds(rowId: String, call: String, action: () -> Unit) {
    try {
        action()
    } catch (_: IndexOutOfBoundsException) {
        println("PASS:$rowId:$call:IndexOutOfBoundsException")
        return
    }
    throw IllegalStateException("$rowId $call did not throw IndexOutOfBoundsException")
}

private fun expectIllegalArgument(rowId: String, call: String, action: () -> Unit) {
    try {
        action()
    } catch (_: IllegalArgumentException) {
        println("PASS:$rowId:$call:IllegalArgumentException")
        return
    }
    throw IllegalStateException("$rowId $call did not throw IllegalArgumentException")
}

@OptIn(ExperimentalEncodingApi::class)
fun main() {
    expect(DECODE_ROW, "producer-default", producerDecodeDefault(), "Hello")
    expect(CHAR_SEQUENCE_ROW, "producer-default", producerDecodeToByteStringCharsDefault(), "Hello")
    expect(BYTE_ARRAY_ROW, "producer-default", producerDecodeToByteStringArrayDefault(), "Hello")
    expect(BYTE_STRING_ROW, "producer-default", producerDecodeToByteStringDefault(), "Hello")
    expect(INTO_ARRAY_ROW, "producer-default", producerDecodeIntoByteArrayDefault(), "5:Hello**")

    expect(DECODE_ROW, "all-defaults", Base64.decode(encodedByteString).decodeToString(), "Hello")
    expect(DECODE_ROW, "default-end", Base64.decode(encodedByteString, startIndex = 4).decodeToString(), "lo")
    expect(DECODE_ROW, "default-start", Base64.decode(encodedByteString, endIndex = 4).decodeToString(), "Hel")
    expect(DECODE_ROW, "explicit-range", Base64.decode(encodedByteString, 0, 4).decodeToString(), "Hel")
    expectIndexOutOfBounds(DECODE_ROW, "negative-start") {
        Base64.decode(encodedByteString, startIndex = -1)
    }
    expectIllegalArgument(DECODE_ROW, "reversed-range") {
        Base64.decode(encodedByteString, startIndex = 4, endIndex = 0)
    }

    expect(CHAR_SEQUENCE_ROW, "all-defaults", Base64.decodeToByteString(encodedChars).decodeToString(), "Hello")
    expect(CHAR_SEQUENCE_ROW, "default-end", Base64.decodeToByteString(encodedChars, startIndex = 4).decodeToString(), "lo")
    expect(CHAR_SEQUENCE_ROW, "default-start", Base64.decodeToByteString(encodedChars, endIndex = 4).decodeToString(), "Hel")
    expectIndexOutOfBounds(CHAR_SEQUENCE_ROW, "past-end") {
        Base64.decodeToByteString(encodedChars, endIndex = encodedChars.length + 1)
    }
    expectIllegalArgument(CHAR_SEQUENCE_ROW, "reversed-range") {
        Base64.decodeToByteString(encodedChars, startIndex = 4, endIndex = 0)
    }

    expect(BYTE_ARRAY_ROW, "all-defaults", Base64.decodeToByteString(encodedArray).decodeToString(), "Hello")
    expect(BYTE_ARRAY_ROW, "default-end", Base64.decodeToByteString(encodedArray, startIndex = 4).decodeToString(), "lo")
    expect(BYTE_ARRAY_ROW, "default-start", Base64.decodeToByteString(encodedArray, endIndex = 4).decodeToString(), "Hel")
    expectIndexOutOfBounds(BYTE_ARRAY_ROW, "past-end") {
        Base64.decodeToByteString(encodedArray, endIndex = encodedArray.size + 1)
    }
    expectIllegalArgument(BYTE_ARRAY_ROW, "reversed-range") {
        Base64.decodeToByteString(encodedArray, startIndex = 4, endIndex = 0)
    }

    expect(BYTE_STRING_ROW, "all-defaults", Base64.decodeToByteString(encodedByteString).decodeToString(), "Hello")
    expect(BYTE_STRING_ROW, "default-end", Base64.decodeToByteString(encodedByteString, startIndex = 4).decodeToString(), "lo")
    expect(BYTE_STRING_ROW, "default-start", Base64.decodeToByteString(encodedByteString, endIndex = 4).decodeToString(), "Hel")
    expectIndexOutOfBounds(BYTE_STRING_ROW, "past-end") {
        Base64.decodeToByteString(encodedByteString, endIndex = encodedByteString.size + 1)
    }
    expectIllegalArgument(BYTE_STRING_ROW, "reversed-range") {
        Base64.decodeToByteString(encodedByteString, startIndex = 4, endIndex = 0)
    }

    val defaultDestination = ByteArray(7) { '*'.code.toByte() }
    val defaultCount = Base64.decodeIntoByteArray(encodedByteString, defaultDestination)
    expect(INTO_ARRAY_ROW, "all-defaults", "$defaultCount:${defaultDestination.decodeToString()}", "5:Hello**")

    val defaultOffsetDestination = ByteArray(5) { '*'.code.toByte() }
    val defaultOffsetCount = Base64.decodeIntoByteArray(
        encodedByteString, defaultOffsetDestination, startIndex = 4, endIndex = 8
    )
    expect(INTO_ARRAY_ROW, "default-destination-offset", "$defaultOffsetCount:${defaultOffsetDestination.decodeToString()}", "2:lo***")

    val defaultStartDestination = ByteArray(7) { '*'.code.toByte() }
    val defaultStartCount = Base64.decodeIntoByteArray(
        encodedByteString, defaultStartDestination, destinationOffset = 1, endIndex = 4
    )
    expect(INTO_ARRAY_ROW, "default-start", "$defaultStartCount:${defaultStartDestination.decodeToString()}", "3:*Hel***")

    val defaultEndDestination = ByteArray(7) { '*'.code.toByte() }
    val defaultEndCount = Base64.decodeIntoByteArray(
        encodedByteString, defaultEndDestination, destinationOffset = 1, startIndex = 4
    )
    expect(INTO_ARRAY_ROW, "default-end", "$defaultEndCount:${defaultEndDestination.decodeToString()}", "2:*lo****")

    expectIndexOutOfBounds(INTO_ARRAY_ROW, "negative-destination-offset") {
        Base64.decodeIntoByteArray(encodedByteString, ByteArray(8), destinationOffset = -1)
    }
    expectIllegalArgument(INTO_ARRAY_ROW, "reversed-range") {
        Base64.decodeIntoByteArray(encodedByteString, ByteArray(8), startIndex = 4, endIndex = 0)
    }
}
