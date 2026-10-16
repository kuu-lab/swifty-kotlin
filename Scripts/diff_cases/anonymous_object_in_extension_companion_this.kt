// KUU-2231: Adapted from Kotlin 2.3.10's pinned
// compiler/testData/codegen/box/localClasses/anonymousObjectInExtension.kt.
// Upstream commit: 679366a83f99851b42f64795f10ed803ff011c73
// Upstream source SHA-256: 6cd6acafc170eef87bc1903f6e8cfaee38aaf879d7ad8814c48163d4f4fe51b9
fun WithCompanion.test(): String {
    object : WithCompanion(this) {}
    return "OK"
}

open class WithCompanion(a: WithCompanion.Companion) {
    companion object
}

fun box(): String {
    return WithCompanion(WithCompanion.Companion).test()
}

open class OverloadedReceiver(val selected: String) {
    constructor(value: OverloadedReceiver) : this("extension")
    constructor(value: Companion) : this("companion")
    companion object
}

fun OverloadedReceiver.chooseReceiver(): String = object : OverloadedReceiver(this) {}.selected

open class AnyReceiver(val value: Any?)

fun WithCompanion.anyReceiverArgumentIsTheExtensionReceiver(): Boolean =
    object : AnyReceiver(this) {}.value is WithCompanion

fun WithCompanion.explicitCompanionArgument(): String {
    object : WithCompanion(WithCompanion.Companion) {}
    return "explicit"
}

fun WithCompanion.Companion.companionExtensionArgument(): String {
    object : WithCompanion(this) {}
    return "companion extension"
}

fun WithCompanion.withoutAnonymousObject(): String {
    val receiver: WithCompanion = this
    return if (receiver is WithCompanion) "plain" else "unreachable"
}

fun main() {
    println(box())
    println(OverloadedReceiver("seed").chooseReceiver())
    println(WithCompanion(WithCompanion.Companion).anyReceiverArgumentIsTheExtensionReceiver())
    println(WithCompanion(WithCompanion.Companion).explicitCompanionArgument())
    println(WithCompanion.Companion.companionExtensionArgument())
    println(WithCompanion(WithCompanion.Companion).withoutAnonymousObject())
}
