/*
 * Copyright 2017-2023 JetBrains s.r.o. and respective authors and developers.
 * Licensed under the Apache License, Version 2.0.
 * Derived from pinned kotlinx-io 0.9.1 core/common/src/files/Paths.kt.
 */
package kotlinx.io.files

import kotlinx.io.Sink
import kotlinx.io.Source
import kotlinx.io.buffered
import kotlin.jvm.JvmName

@Deprecated(
    message = "Use FileSystem.source instead",
    replaceWith = ReplaceWith(
        expression = "SystemFileSystem.source(this).buffered()",
        imports = arrayOf("kotlinx.io.files.FileSystem")
    ),
    level = DeprecationLevel.ERROR
)
@JvmName("sourceDeprecated")
public fun Path.source(): Source = SystemFileSystem.source(this).buffered()

@Deprecated(
    message = "Use FileSystem.sink instead",
    replaceWith = ReplaceWith(
        expression = "SystemFileSystem.sink(this).buffered()",
        imports = arrayOf("kotlinx.io.files.FileSystem")
    ),
    level = DeprecationLevel.ERROR
)
@JvmName("sinkDeprecated")
public fun Path.sink(): Sink = SystemFileSystem.sink(this).buffered()
