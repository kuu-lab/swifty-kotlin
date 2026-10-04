package golden.sema

import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.InvocationKind

@OptIn(ExperimentalContracts::class)
fun invocationKindEntries(): kotlin.enums.EnumEntries<InvocationKind> =
    InvocationKind.entries

@OptIn(ExperimentalContracts::class)
fun invocationKindValueOf(): InvocationKind =
    InvocationKind.valueOf("EXACTLY_ONCE")

@OptIn(ExperimentalContracts::class)
fun invocationKindValues(): Array<InvocationKind> =
    InvocationKind.values()
