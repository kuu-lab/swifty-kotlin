package io.segmenttypeprobe

import kotlinx.io.Segment

fun retainPublicSegmentType(value: Segment?): Segment? = value

fun main() {
    check(retainPublicSegmentType(null) == null)
    println("segment-public-type:ok")
}
