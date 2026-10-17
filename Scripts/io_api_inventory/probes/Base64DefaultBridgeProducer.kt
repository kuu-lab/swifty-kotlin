package f02base64producer

import kotlinx.io.bytestring.ByteString
import kotlinx.io.bytestring.decode
import kotlinx.io.bytestring.decodeIntoByteArray
import kotlinx.io.bytestring.decodeToByteString
import kotlinx.io.bytestring.decodeToString
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

private val encoded = "SGVsbG8="
private val encodedChars: CharSequence = encoded
private val encodedArray = encoded.encodeToByteArray()
private val encodedByteString = ByteString(encodedArray)

@OptIn(ExperimentalEncodingApi::class)
public fun decodeDefault(): String = Base64.decode(encodedByteString).decodeToString()

@OptIn(ExperimentalEncodingApi::class)
public fun decodeToByteStringCharsDefault(): String = Base64.decodeToByteString(encodedChars).decodeToString()

@OptIn(ExperimentalEncodingApi::class)
public fun decodeToByteStringArrayDefault(): String = Base64.decodeToByteString(encodedArray).decodeToString()

@OptIn(ExperimentalEncodingApi::class)
public fun decodeToByteStringDefault(): String = Base64.decodeToByteString(encodedByteString).decodeToString()

@OptIn(ExperimentalEncodingApi::class)
public fun decodeIntoByteArrayDefault(): String {
    val destination = ByteArray(7) { '*'.code.toByte() }
    val count = Base64.decodeIntoByteArray(encodedByteString, destination)
    return "$count:${destination.decodeToString()}"
}
