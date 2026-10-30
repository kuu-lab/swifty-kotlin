package kotlin.text

import kotlin.OverloadResolutionByLambdaReturnType
import kotlin.experimental.ExperimentalTypeInference
import kotlin.jvm.JvmName

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
fun String.replaceFirstChar(transform: (Char) -> Char): String = null!!

@SinceKotlin("1.5")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@JvmName("replaceFirstCharWithCharSequence")
fun String.replaceFirstChar(transform: (Char) -> CharSequence): String = null!!
