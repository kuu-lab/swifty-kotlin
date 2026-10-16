package kuu2588.segmentwritebackdatanegative

import kotlinx.io.Segment

fun segmentWriteBackDataMustRemainInternal(segment: Segment, data: ByteArray) {
    segment.writeBackData(data, 1)
}
