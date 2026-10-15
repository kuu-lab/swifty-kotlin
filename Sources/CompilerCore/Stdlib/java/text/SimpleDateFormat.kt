package java.text

import java.util.Date
import kotlin.internal.KsSymbolName

/** Source-backed subset of Java's SimpleDateFormat used by Forge's date parser. */
public class SimpleDateFormat(
    private val pattern: String,
) {
    public fun parse(source: String): Date = Date(__kkSimpleDateFormatParse(pattern, source))
}

@KsSymbolName("__kk_simple_date_format_parse")
private external fun __kkSimpleDateFormatParse(pattern: String, source: String): Long
