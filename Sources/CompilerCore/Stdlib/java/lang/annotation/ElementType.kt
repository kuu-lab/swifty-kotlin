package java.lang.annotation

/** JDK `java.lang.annotation.ElementType` — the declaration contexts an
 * annotation type may target. */
public enum class ElementType {
    TYPE,
    FIELD,
    METHOD,
    PARAMETER,
    CONSTRUCTOR,
    LOCAL_VARIABLE,
    ANNOTATION_TYPE,
    PACKAGE,
    TYPE_USE,
    TYPE_PARAMETER,
    MODULE,
    RECORD_COMPONENT,
}
