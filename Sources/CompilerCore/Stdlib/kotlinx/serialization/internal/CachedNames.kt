/*
 * Copyright 2017-2020 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */
package kotlinx.serialization.internal

import kotlinx.serialization.descriptors.*

internal interface CachedNames {

    public val serialNames: Set<String>
}
