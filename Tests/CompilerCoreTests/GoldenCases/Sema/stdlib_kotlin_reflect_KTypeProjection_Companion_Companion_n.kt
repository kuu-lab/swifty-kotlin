package golden.sema

import kotlin.reflect.KType
import kotlin.reflect.KTypeProjection

fun companionStar(): KTypeProjection = KTypeProjection.STAR

fun companionExplicitStar(): KTypeProjection = KTypeProjection.Companion.STAR

fun companionInvariant(type: KType): KTypeProjection = KTypeProjection.invariant(type)

fun companionContravariant(type: KType): KTypeProjection = KTypeProjection.contravariant(type)

fun companionCovariant(type: KType): KTypeProjection = KTypeProjection.covariant(type)

fun companionExplicitInvariant(type: KType): KTypeProjection =
    KTypeProjection.Companion.invariant(type)
