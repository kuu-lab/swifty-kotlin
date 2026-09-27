@file:Suppress("DEPRECATION_ERROR")
@file:OptIn(ExperimentalUnsignedTypes::class, kotlinx.cinterop.ExperimentalForeignApi::class)

package golden.sema

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

fun blobDefaultArguments(blob: ImmutableBlob): CPointer<ByteVar> {
    val bytes = blob.toByteArray()
    return if (bytes.size > 0) blob.asCPointer() else blob.asCPointer(1)
}
