#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-4608: an in-place `plusAssign`/`minusAssign`/`timesAssign` call does not
/// rebind the local, so member smart casts on its stable receiver survive the
/// compound write. Writes that rebind the local (binary fallback, `++`/`--`,
/// plain assignment, deferred capture) and delegated locals stay conservative.
@Suite
struct CompoundAssignMemberSmartCastTests {
    @Test(arguments: [
        "b += 1",
        "b -= 1",
        "b *= 2"
    ])
    func inPlaceCompoundAssignPreservesMemberSmartCast(write: String) throws {
        _ = try semaContext(from: """
        class Box(val s: String?) {
            operator fun plusAssign(i: Int) {}
            operator fun minusAssign(i: Int) {}
            operator fun timesAssign(i: Int) {}
        }
        fun test() {
            var b = Box("hello")
            \(write)
            if (b.s != null) println(b.s.length)
            requireNotNull(b.s)
            println(b.s.length)
        }
        """)
    }

    @Test func binaryCompoundAssignRebindInvalidatesMemberSmartCast() throws {
        _ = try semaContext(from: """
        class Box(val s: String?) { operator fun plus(i: Int): Box = Box(null) }
        fun test() {
            var b = Box("hello")
            b += 1
            if (b.s != null) println(b.s.length)
        }
        """, expecting: [.error("KSWIFTK-SEMA-0026", containing: "Only safe")])
    }

    @Test func plainReassignmentAfterInPlaceCompoundAssignInvalidatesMemberSmartCast() throws {
        _ = try semaContext(from: """
        class Box(val s: String?) { operator fun plusAssign(i: Int) {} }
        fun test() {
            var b = Box("hello")
            b += 1
            b = Box(null)
            if (b.s != null) println(b.s.length)
        }
        """, expecting: [.error("KSWIFTK-SEMA-0026", containing: "Only safe")])
    }

    @Test func incrementDecrementInvalidatesMemberSmartCast() throws {
        _ = try semaContext(from: """
        class Box(val s: String?) { operator fun inc(): Box = Box("next") }
        fun test() {
            var b = Box("hello")
            b++
            if (b.s != null) println(b.s.length)
        }
        """, expecting: [.error("KSWIFTK-SEMA-0026", containing: "Only safe")])
    }

    @Test func capturedInPlaceCompoundAssignInvalidatesMemberSmartCast() throws {
        _ = try semaContext(from: """
        class Box(val s: String?) { operator fun plusAssign(i: Int) {} }
        fun test() {
            var b = Box("hello")
            val write = { b += 1 }
            if (b.s != null) println(b.s.length)
            write()
        }
        """, expecting: [.error("KSWIFTK-SEMA-0026", containing: "Only safe")])
    }

    // A delegated local re-evaluates `getValue` on every read, so it is never a
    // stable smart-cast receiver even without any reassignment; kotlinc rejects
    // the same program ("smart cast ... is impossible, because 's' is a
    // delegated property").
    @Test func delegatedLocalReceiverIsNotStable() throws {
        _ = try semaContext(from: """
        class Box(val s: String?)
        class BoxDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): Box = Box("delegate")
            operator fun setValue(thisRef: Any?, property: Any?, value: Box) {}
        }
        fun test() {
            var b by BoxDelegate()
            if (b.s != null) println(b.s.length)
        }
        """, expecting: [.error("KSWIFTK-SEMA-0026", containing: "Only safe")])
    }
}
#endif
