package golden.sema

import kotlin.reflect.KParameter
import kotlin.reflect.KType

fun inspectIndex(p: KParameter): Int = p.index

fun inspectName(p: KParameter): String? = p.name

fun inspectType(p: KParameter): KType = p.type

fun inspectOptional(p: KParameter): Boolean = p.isOptional

fun inspectKind(p: KParameter): Int = p.kind
