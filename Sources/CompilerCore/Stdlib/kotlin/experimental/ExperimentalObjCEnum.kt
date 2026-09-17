package kotlin.experimental

// Upstream declares this marker under kotlin.experimental (post-2.3.10);
// no dedicated v2.3.10 owner file exists yet.
@kotlin.annotation.Target(AnnotationTarget.ANNOTATION_CLASS)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.RequiresOptIn(level = RequiresOptIn.Level.ERROR)
public annotation class ExperimentalObjCEnum
