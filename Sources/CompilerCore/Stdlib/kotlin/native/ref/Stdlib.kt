/*
 * KSP-1254: Kotlin/Native reference API nominal declarations.
 *
 * The WeakReference constructor and members remain residual runtime-backed
 * bridges until KSP-1255/KSP-1256. This file owns only the top-level nominal
 * and factory surface required by Kotlin 2.3.10.
 */

package kotlin.native.ref

import kotlin.experimental.ExperimentalNativeApi
import kotlin.internal.KsSymbolName
import kotlin.native.internal.ExportForCompiler

@ExperimentalNativeApi
public class WeakReference<T : Any> private constructor()

@PublishedApi
internal abstract class WeakReferenceImpl {
    abstract fun get(): Any?
}

@ExperimentalNativeApi
@SinceKotlin("1.9")
public sealed interface Cleaner

@ExperimentalNativeApi
@KsSymbolName("kk_cleaner_create")
private external fun createCleanerBridge(
    resource: Any?,
    cleanupAction: Any?
): Cleaner

@ExperimentalNativeApi
@SinceKotlin("1.9")
@ExportForCompiler
public fun <T> createCleaner(
    resource: T,
    cleanupAction: (resource: T) -> Unit
): Cleaner = createCleanerBridge(resource, cleanupAction)
