package kotlin.text

import java.util.regex.Pattern

public fun Regex.toPattern(): Pattern = Pattern.fromRegex(this)
