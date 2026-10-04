/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 */

package kotlinx.coroutines.channels

public enum class BufferOverflow {
    SUSPEND,
    DROP_OLDEST,
    DROP_LATEST
}
