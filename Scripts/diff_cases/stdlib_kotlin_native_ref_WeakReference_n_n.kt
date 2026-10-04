// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.ref APIs are Kotlin/Native-only and are not available in JVM kotlinc.
@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

import kotlin.native.ref.WeakReference

fun createWeakReference(value: String): WeakReference<String> = WeakReference(value)
