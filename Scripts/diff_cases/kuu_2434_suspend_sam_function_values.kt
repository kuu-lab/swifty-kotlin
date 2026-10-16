// KUU-2434: Adapt non-suspend function values to suspend SAM parameters.
// Source: JetBrains/Kotlin v2.3.10 at 679366a83f99851b42f64795f10ed803ff011c73,
// compiler/testData/codegen/box/sam/constructors/suspendSamConstructorAdaptation.kt
// Git blob: 2eef7a19f115f3760127b5d45e54e4f27dbb5ec8; raw SHA-256: 3849f16f7a77a19e2127a8fd3ed5ee755be01be47684666cb1ae7be5b332e1b9.
// JetBrains/Kotlin applies Apache-2.0 to this source (see license/LICENSE.txt).
// The public test is followed by a minimal regression from KUU-2434.
// DUMP_IR
// FIR_IDENTICAL

fun interface FunInterface {
    suspend operator fun invoke()
}

fun func(f: FunInterface) = Unit

fun box(): String {
    val lambda: () -> Unit = { }
    func(f = lambda)
    func(lambda)
    func { }
    return "OK"
}

fun interface SuspendAction { suspend operator fun invoke() }
fun call(action: SuspendAction) {}
fun probe(action: () -> Unit) { call(action) }
fun minimalBox(): String { probe {}; return "OK" }

fun main() {
    println(box())
    println(minimalBox())
}
