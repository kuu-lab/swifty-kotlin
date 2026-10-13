package kotlin.text

import java.util.regex.Pattern

/** Adapts this regex to the bundled `java.util.regex.Pattern` facade. */
public fun Regex.toPattern(): Pattern = Pattern.fromRegex(this)
