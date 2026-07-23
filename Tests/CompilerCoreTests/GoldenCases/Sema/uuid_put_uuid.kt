@file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

package golden.sema

import kotlin.uuid.Uuid
import kotlin.uuid.putUuid
import kotlin.uuid.getUuid
import java.nio.ByteBuffer

fun writeThenReadUuid(buf: ByteBuffer, u: Uuid): Uuid {
    buf.putUuid(0, u)
    return buf.getUuid(0)
}
