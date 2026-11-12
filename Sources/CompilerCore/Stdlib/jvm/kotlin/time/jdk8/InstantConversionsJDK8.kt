package kotlin.time.jdk8

import java.time.Instant as JavaInstant
import kotlin.time.Instant

public fun Instant.toJavaInstant(): JavaInstant =
    JavaInstant.ofEpochSecond(epochSeconds, nanosecondsOfSecond.toLong())

public fun JavaInstant.toKotlinInstant(): Instant =
    Instant.fromEpochSeconds(getEpochSecond(), getNano())
