#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CompoundAssignStableReceiverSmartCastTests {
    // KUU-4608: an in-place `plusAssign` mutates the receiver without rebinding
    // the captured local, so the stable member smart cast remains valid.
    @Test func inPlacePlusAssignKeepsCapturedMemberSmartCast() throws {
        _ = try semaContext(from: """
        class Box(val s: String?)
        operator fun Box.plusAssign(i: Int) {}
        fun test() {
            var b = Box("ok")
            b += 1
            fun read(): String {
                if (b.s != null) return b.s
                return "fail"
            }
            println(read())
        }
        """)
    }

    @Test func inPlacePlusAssignKeepsDirectMemberSmartCast() throws {
        _ = try semaContext(from: """
        class Box(val s: String?)
        operator fun Box.plusAssign(i: Int) {}
        fun test() {
            var b = Box("ok")
            b += 1
            if (b.s != null) {
                val y: String = b.s
                println(y)
            }
        }
        """)
    }

    // The `plus` fallback is `b = b.plus(1)`, an actual rebinding that can
    // replace the receiver, so the earlier member smart cast must stay invalid.
    @Test func plusFallbackStillInvalidatesMemberSmartCast() throws {
        _ = try semaContext(
            from: """
            class Box(val s: String?)
            operator fun Box.plus(i: Int): Box = this
            fun test() {
                var b = Box("ok")
                if (b.s != null) {
                    b += 1
                    val y: String = b.s
                    println(y)
                }
            }
            """,
            expecting: [.error("KSWIFTK-SEMA-0468", containing: "Initializer type mismatch.")]
        )
    }
}
#endif
