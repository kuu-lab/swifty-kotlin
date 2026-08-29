// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent APIs are Kotlin/Native-only and unavailable in JVM kotlinc.
@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

package diff.native.concurrent

import kotlin.native.concurrent.ObsoleteWorkersApi

@ObsoleteWorkersApi
class ObsoleteWorkersApiUse
