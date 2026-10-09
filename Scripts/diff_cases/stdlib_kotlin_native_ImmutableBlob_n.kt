// CANDIDATE-ONLY: kotlin.native APIs are platform-specific and have no JVM analogue.
@file:Suppress("DEPRECATION_ERROR")
@file:OptIn(ExperimentalUnsignedTypes::class, kotlinx.cinterop.ExperimentalForeignApi::class)

package diff

import kotlin.native.ImmutableBlob
import kotlin.native.asCPointer
import kotlin.native.asUCPointer
import kotlin.native.immutableBlobOf
import kotlin.native.toByteArray
import kotlin.native.toUByteArray
import kotlinx.cinterop.ByteVar
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.UByteVar

fun blobToByteArray(blob: ImmutableBlob): ByteArray = blob.toByteArray(1, blob.size)

fun blobToUByteArray(blob: ImmutableBlob): UByteArray = blob.toUByteArray()

fun blobAsCPointer(blob: ImmutableBlob): CPointer<ByteVar> = blob.asCPointer(2)

fun blobAsUCPointer(blob: ImmutableBlob): CPointer<UByteVar> = blob.asUCPointer()

fun main() {
    val blob = immutableBlobOf(1, 2, 3)
    val bytes = blob.toByteArray()
    val ubytes = blob.toUByteArray()
    println("ok ${bytes.size} ${ubytes.size}")
}
