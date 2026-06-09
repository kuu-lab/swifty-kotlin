@file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

package golden.sema

import kotlin.uuid.Uuid
import kotlin.uuid.putUuid
import kotlin.uuid.uuid

fun writeThenReadUuid(arr: ByteArray, u: Uuid): Uuid {
    arr.putUuid(0, u)
    return arr.uuid(0)
}
