@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package golden.sema

import kotlin.native.ref.Cleaner
import kotlin.native.ref.WeakReference
import kotlin.native.ref.createCleaner

fun weakReferenceType(): WeakReference<String>? = null

fun cleanerType(resource: String?): Cleaner =
    createCleaner(resource) { _: String? -> }
