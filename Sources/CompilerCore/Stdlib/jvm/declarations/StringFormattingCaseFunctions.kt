package kotlin.text

import kotlin.OverloadResolutionByLambdaReturnType
import kotlin.experimental.ExperimentalTypeInference
import kotlin.jvm.JvmName

fun CharSequence.splitToSequence(vararg delimiters: String, ignoreCase: Boolean = null!!, limit: Int = null!!): kotlin.sequences.Sequence<String> = null!!

fun String.format(vararg args: Any?): String = null!!
fun String.format(locale: java.util.Locale?, vararg args: Any?): String = null!!

@Deprecated("Use replaceFirstChar instead.")
fun String.capitalize(): String = null!!

@Deprecated("Use replaceFirstChar instead.")
fun String.decapitalize(): String = null!!

@SinceKotlin("1.5")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@JvmName("replaceFirstCharWithChar")
@kotlin.internal.InlineOnly
public inline fun String.replaceFirstChar(transform: (Char) -> Char): String =
    if (isNotEmpty()) transform(this[0]) + substring(1) else this

@SinceKotlin("1.5")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@JvmName("replaceFirstCharWithCharSequence")
@kotlin.internal.InlineOnly
public inline fun String.replaceFirstChar(transform: (Char) -> CharSequence): String =
    if (isNotEmpty()) transform(this[0]).toString() + substring(1) else this

fun String.toUpperCase(): String = null!!
fun String.toLowerCase(): String = null!!

val String.Companion.CASE_INSENSITIVE_ORDER: Comparator<String> get() = null!!
