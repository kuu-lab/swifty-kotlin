// SKIP-DIFF (DEBT-DIFF-001): kotlin.native APIs are platform-specific and have no JVM analogue.
@file:Suppress("DEPRECATION_ERROR")

package diff

import kotlin.native.ImmutableBlob
import kotlin.native.immutableBlobOf

fun readBlobMembers(blob: ImmutableBlob): Int {
    val size = blob.size
    val first = blob.get(0)
    val indexed = blob[1]
    val iterator = blob.iterator()
    return if (size > 0 && first == indexed && iterator.hasNext()) 1 else 0
}

fun iterateCreatedBlob(): Int {
    val created = immutableBlobOf(1, 2, 3)
    var count = 0
    for (element in created) {
        if (element > 0) {
            count += 1
        }
    }
    return count
}

fun main() {
    println("ok")
}
