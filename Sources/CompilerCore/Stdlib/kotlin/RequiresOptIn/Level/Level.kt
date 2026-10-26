package kotlin

import kotlin.enums.enumEntries

public val RequiresOptIn.Level.entries: kotlin.enums.EnumEntries<RequiresOptIn.Level>
    get() = enumEntries<RequiresOptIn.Level>()

public fun RequiresOptIn.Level.valueOf(value: String): RequiresOptIn.Level =
    enumValueOf<RequiresOptIn.Level>(value)

public fun RequiresOptIn.Level.values(): Array<RequiresOptIn.Level> =
    enumValues<RequiresOptIn.Level>()
