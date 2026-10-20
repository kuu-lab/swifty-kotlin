package kotlin

@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.RUNTIME)
public annotation class Metadata(
    val k: Int = 1,
    val mv: IntArray = [],
    val bv: IntArray = [1, 0, 3],
    val d1: Array<String> = [],
    val d2: Array<String> = [],
    val xs: String = "",
    val pn: String = "",
    val xi: Int = 0
)
