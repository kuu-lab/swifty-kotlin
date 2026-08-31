package golden.sema

import kotlin.enums.enumEntries

enum class Color { RED, GREEN }

fun colorEntries(): kotlin.enums.EnumEntries<Color> = enumEntries<Color>()
