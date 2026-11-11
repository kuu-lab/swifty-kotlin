package kotlin

@kotlin.annotation.Target(AnnotationTarget.ANNOTATION_CLASS)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class RequiresOptIn(
    val message: String = "",
    val level: Level = Level.ERROR
) {
    public enum class Level {
        WARNING,
        ERROR
    }
}
