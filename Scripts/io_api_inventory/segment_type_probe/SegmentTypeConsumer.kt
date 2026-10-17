package io.segmenttypeprobe.consumer

import io.segmenttypeprobe.producer.retainSegmentAcrossLibraryBoundary

fun main() {
    check(retainSegmentAcrossLibraryBoundary(null) == null)
    println("segment-library-boundary:ok")
}
