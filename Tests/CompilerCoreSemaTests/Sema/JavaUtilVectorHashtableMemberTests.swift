@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

/// KUU-4428: bundled java.util.Vector/Hashtable are JVM classes, not typealiases.
/// Modelling them as `typealias Vector<E> = ArrayList<E>` /
/// `typealias Hashtable<K, V> = HashMap<K, V>` forced `elements()`/`keys()`/
/// `contains(value)` to live in source-backed extensions that only resolved
/// through the importless atomic-stdlib fallback, so ordinary member calls
/// without an explicit extension import were rejected with SEMA-0024.
@Suite
struct JavaUtilVectorHashtableMemberTests {
    @Test
    func vectorAndHashtableMembersResolveWithoutExtensionImport() throws {
        let context = makeContextFromSource("""
        import java.util.Vector
        import java.util.Hashtable
        import java.util.Properties
        import java.util.Enumeration

        fun main() {
            val v = Vector<String>()
            v.add("a")
            val en: Enumeration<String> = v.elements()
            println(en.toList())
            println(Vector<Int>(listOf(1, 2)).size)
            println(v.firstElement())
            println(v.lastElement())

            val h = Hashtable<String, Int>()
            h["k"] = 1
            println(h.elements().toList())
            println(h.keys().toList())
            println(h.contains(1))
            println(h.containsValue(1))

            val p = Properties()
            p.setProperty("a", "b")
            println(p.propertyNames().toList())
        }
        """)
        do { try runSema(context) } catch {}
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test
    func arrayListReceiverStillRejectsElements() throws {
        let context = makeContextFromSource("""
        fun main() {
            val a = arrayListOf<String>()
            a.elements()
        }
        """)
        do { try runSema(context) } catch {}
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0024" }, "\(errors)")
    }
}
