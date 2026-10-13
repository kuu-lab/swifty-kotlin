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

/**
 * Returns [RawSource] for the given file or throws if path is not a file or does not exist
 *
 * Use of this method is deprecated with warning since kotlinx-io 0.3.0, with error since 0.8.0,
 * and it will be removed in the future.
 */
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

/**
 * Returns [RawSink] for the given path, creates file if it doesn't exist, throws if it's a directory,
 * overwrites contents.
 *
 * Use of this method is deprecated with warning since kotlinx-io 0.3.0, with error since 0.8.0,
 * and it will be removed in the future.
 */
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
