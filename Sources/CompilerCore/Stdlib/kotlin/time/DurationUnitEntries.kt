package kotlin.time

import kotlin.enums.enumEntries

public val DurationUnit.entries: kotlin.enums.EnumEntries<DurationUnit>
    get() = enumEntries<DurationUnit>()
