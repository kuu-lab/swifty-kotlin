/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENSE.txt file.
 *
 * Derived from kotlinx-io core/common/src/Buffers.kt (tag 0.9.1). `Buffer.snapshot()` is omitted:
 * it requires `kotlinx.io.bytestring.ByteString`, which is bundled separately (KSP-1556).
 */

package kotlinx.io

/**
 * Returns an index of [byte] first occurrence in the range of [startIndex] to [endIndex],
 * or `-1` when the range doesn't contain [byte].
 *
 * The scan terminates at either [endIndex] or buffers' exhaustion, whichever comes first.
 *
 * @param byte the value to find.
 * @param startIndex the start of the range (inclusive) to find [byte], `0` by default.
 * @param endIndex the end of the range (exclusive) to find [byte], [Buffer.size] by default.
 *
 * @throws IllegalStateException when the source is closed.
 * @throws IllegalArgumentException when `startIndex > endIndex` or either of indices is negative.
 *
 * @sample kotlinx.io.samples.KotlinxIoCoreCommonSamples.indexOfByteSample
 */
public fun Buffer.indexOf(byte: Byte, startIndex: Long = 0, endIndex: Long = size): Long {
    // For compatibility with Source.indexOf accept endIndices greater than size and truncate them.
    val endOffset = minOf(endIndex, size)
    checkBounds(size, startIndex, endOffset)
    if (startIndex == endOffset) return -1L

    seek(startIndex) { seg, o ->
        if (o == -1L) {
            return -1L
        }
        var segment: Segment? = seg
        var offset = o
        do {
            check(endOffset > offset)
            val seg = segment!!
            val idx = seg.indexOf(
                byte,
                // If start index within this segment, the diff will be positive and
                // we'll scan the segment starting from the corresponding offset.
                // Otherwise, the diff will be negative and we'll scan the segment from the beginning.
                maxOf((startIndex - offset).toInt(), 0),
                // If endOffset is within this segment - scan until it, otherwise - scan whole segment.
                minOf(seg.size, (endOffset - offset).toInt())
            )
            if (idx != -1) {
                // offset corresponds to the segment's start, idx - to offset within the segment.
                return offset + idx.toLong()
            }
            offset += seg.size
            segment = seg.next
        } while (segment != null && offset < endOffset)
        return -1L
    }
}
