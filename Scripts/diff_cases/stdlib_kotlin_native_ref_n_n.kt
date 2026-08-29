// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.ref APIs are Kotlin/Native-only and are not available in JVM kotlinc.
@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

import kotlin.native.ref.Cleaner
import kotlin.native.ref.WeakReference
import kotlin.native.ref.createCleaner

fun weakReferenceType(): WeakReference<String>? = null

fun cleanerType(resource: String?): Cleaner =
    createCleaner(resource) { _: String? -> }
