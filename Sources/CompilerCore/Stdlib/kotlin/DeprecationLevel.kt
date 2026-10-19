package kotlin

public enum class DeprecationLevel {
    WARNING,
    ERROR,
    HIDDEN
}

public val DeprecationLevel.entries: kotlin.enums.EnumEntries<DeprecationLevel>
    get() = enumEntries<DeprecationLevel>()
