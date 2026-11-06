// KUU-4015: primitive member calls with a non-null `Nothing` operand
// (`TODO()`) resolve when exactly one overload remains applicable —
// `mod`/`floorDiv` pick the Int/UInt-parameter winner, unsigned receivers
// keep their wider result on `floorDiv`, and `Char.plus(Int)` is the only
// member overload. kotlinc rejects the ambiguous arithmetic ops, which the
// Sema unit tests cover; this case pins the accepted set end-to-end.
fun main() {
    val x = 5
    val u: UInt = 1u
    val c = 'a'
    try {
        x.mod(TODO())
    } catch (e: NotImplementedError) {
        println("mod")
    }
    try {
        x.floorDiv(TODO())
    } catch (e: NotImplementedError) {
        println("floorDiv")
    }
    try {
        u.mod(TODO())
    } catch (e: NotImplementedError) {
        println("uMod")
    }
    try {
        u.floorDiv(TODO())
    } catch (e: NotImplementedError) {
        println("uFloorDiv")
    }
    try {
        c.plus(TODO())
    } catch (e: NotImplementedError) {
        println("cPlus")
    }
}
