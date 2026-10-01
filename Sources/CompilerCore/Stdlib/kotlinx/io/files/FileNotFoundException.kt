/*
 * Copyright 2017-2024 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 */
package kotlinx.io.files

import kotlinx.io.IOException

/** Signals that a file or directory requested from the filesystem is absent. */
public open class FileNotFoundException : IOException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}
