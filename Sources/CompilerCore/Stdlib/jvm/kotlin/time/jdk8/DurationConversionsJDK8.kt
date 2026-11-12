package kotlin.time.jdk8

import java.time.Duration as JavaDuration
import kotlin.time.Duration
import kotlin.time.DurationUnit
import kotlin.time.toDuration

public fun Duration.toJavaDuration(): JavaDuration =
    JavaDuration.ofSeconds(inWholeSeconds, nanosecondsComponent.toLong())

public fun JavaDuration.toKotlinDuration(): Duration =
    getSeconds().toDuration(DurationUnit.SECONDS) + getNano().toDuration(DurationUnit.NANOSECONDS)
