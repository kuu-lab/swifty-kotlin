package kotlin

// KSP-1129: source-backed enum helper API for InvocationKind.
@Suppress("KSWIFTK-SEMA-OPT-IN")
public val kotlin.contracts.InvocationKind.entries: kotlin.enums.EnumEntries<kotlin.contracts.InvocationKind>
    get() = enumEntries<kotlin.contracts.InvocationKind>()

@Suppress("KSWIFTK-SEMA-OPT-IN")
public fun kotlin.contracts.InvocationKind.valueOf(value: String): kotlin.contracts.InvocationKind =
    enumValueOf<kotlin.contracts.InvocationKind>(value)

@Suppress("KSWIFTK-SEMA-OPT-IN")
public fun kotlin.contracts.InvocationKind.values(): Array<kotlin.contracts.InvocationKind> =
    enumValues<kotlin.contracts.InvocationKind>()
