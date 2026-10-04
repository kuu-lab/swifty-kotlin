package golden.sema

import kotlin.text.RegexOption

fun entries(): kotlin.enums.EnumEntries<RegexOption> = RegexOption.entries

fun valueOf(): RegexOption = RegexOption.valueOf("CANON_EQ")

fun values(): Array<RegexOption> = RegexOption.values()
