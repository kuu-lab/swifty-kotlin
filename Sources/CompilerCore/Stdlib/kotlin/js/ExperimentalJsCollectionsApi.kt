package kotlin.js

/** Requires opt-in for Kotlin/JS collection view APIs. */
@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
@MustBeDocumented
@Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.BINARY)
@SinceKotlin("2.0")
public annotation class ExperimentalJsCollectionsApi
