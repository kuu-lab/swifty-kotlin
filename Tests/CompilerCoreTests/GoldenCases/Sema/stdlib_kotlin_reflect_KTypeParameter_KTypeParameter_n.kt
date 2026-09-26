package golden.sema

import kotlin.reflect.KClassifier
import kotlin.reflect.KType
import kotlin.reflect.KTypeParameter
import kotlin.reflect.KVariance

fun name(parameter: KTypeParameter): String = parameter.name

fun reified(parameter: KTypeParameter): Boolean = parameter.isReified

fun bounds(parameter: KTypeParameter): List<KType> = parameter.upperBounds

fun variance(parameter: KTypeParameter): KVariance = parameter.variance

fun classifier(parameter: KTypeParameter): KClassifier = parameter
