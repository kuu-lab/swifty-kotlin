package kotlin.native

@kotlin.annotation.Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.VALUE_PARAMETER,
    AnnotationTarget.FUNCTION
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class ObjCName(
    val name: String = "",
    val swiftName: String = "",
    val exact: Boolean = false
)

@kotlin.annotation.Target(
    AnnotationTarget.FUNCTION,
    AnnotationTarget.CLASS
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class CName(
    val externName: String = "",
    val shortName: String = ""
)

@kotlin.annotation.Target(AnnotationTarget.FUNCTION)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class ObjCSignatureOverride

@kotlin.annotation.Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class HidesFromObjC

@kotlin.annotation.Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class ShouldRefineInSwift

@kotlin.annotation.Target(AnnotationTarget.ANNOTATION_CLASS)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class RefinesInSwift

@kotlin.annotation.Target(
    AnnotationTarget.PROPERTY,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.CLASS
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.native.HidesFromObjC
@kotlin.experimental.ExperimentalObjCRefinement
public annotation class HiddenFromObjC
