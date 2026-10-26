package kotlin

import kotlin.enums.enumEntries

public enum class DeprecationLevel {
    WARNING,
    ERROR,
    HIDDEN
}

public val DeprecationLevel.entries: kotlin.enums.EnumEntries<DeprecationLevel>
    get() = enumEntries<DeprecationLevel>()
