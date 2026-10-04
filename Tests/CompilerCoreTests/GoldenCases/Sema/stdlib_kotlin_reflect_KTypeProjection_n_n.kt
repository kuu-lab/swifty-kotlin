package golden.sema

import kotlin.reflect.KType
import kotlin.reflect.KTypeProjection
import kotlin.reflect.KVariance

fun constructProjection(variance: KVariance?, type: KType?): KTypeProjection =
    KTypeProjection(variance, type)

fun projectionCompanion(): KTypeProjection.Companion = KTypeProjection.Companion
