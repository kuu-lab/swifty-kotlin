@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package golden.sema

import kotlin.native.ref.WeakReference

fun createWeakReference(value: String): WeakReference<String> = WeakReference(value)
