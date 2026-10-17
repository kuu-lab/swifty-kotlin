package java.text

import java.util.Date
import kotlin.internal.KsSymbolName

public class SimpleDateFormat(
    private val pattern: String,
) {
    public fun parse(source: String): Date = Date(__kkSimpleDateFormatParse(pattern, source))
}

@KsSymbolName("__kk_simple_date_format_parse")
private external fun __kkSimpleDateFormatParse(pattern: String, source: String): Long
