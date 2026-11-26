package kotlin

import kotlin.enums.enumEntries

public enum class LazyThreadSafetyMode {
    SYNCHRONIZED,
    PUBLICATION,
    NONE
}

public val LazyThreadSafetyMode.entries: kotlin.enums.EnumEntries<LazyThreadSafetyMode>
    get() = enumEntries<LazyThreadSafetyMode>()
