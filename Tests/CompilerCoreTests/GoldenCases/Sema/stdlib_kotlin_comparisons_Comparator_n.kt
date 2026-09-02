import kotlin.comparisons.then
import kotlin.comparisons.thenDescending

fun combine(primary: Comparator<String>, secondary: Comparator<Any>): Comparator<String> =
    primary then secondary

fun combineDescending(primary: Comparator<String>, secondary: Comparator<Any>): Comparator<String> =
    primary thenDescending secondary

fun combineNullable(primary: Comparator<String?>, secondary: Comparator<Any?>): Comparator<String?> =
    primary.then(secondary)

fun combineNullableDescending(
    primary: Comparator<String?>,
    secondary: Comparator<Any?>
): Comparator<String?> = primary.thenDescending(secondary)
