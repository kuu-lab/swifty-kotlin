@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct JavaCollectionSizeTests {
    @Test
    func javaCollectionListSizes() throws {
        let source = """
        import java.util.Collections
        import java.util.LinkedList
        fun <L : List<Int>> bounded(values: L) = Collections.checkedList(values, Int::class.java).size
        fun main() {
            val checked = Collections.checkedList(listOf(1), Int::class.java)
            val backing = mutableListOf(1, 2)
            val synchronized = Collections.synchronizedList(backing)
            val unmodifiable = Collections.unmodifiableList(backing)
            println(checked.size)
            println(synchronized.size)
            println(unmodifiable.size)
            println(LinkedList(backing).size)
        }
        """
        let context = makeContextFromSource(source)
        do { try runSema(context) } catch {}
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test
    func checkedListRetainsInvariantElementType() throws {
        let context = makeContextFromSource("""
        import java.util.Collections
        fun wrong(values: MutableList<Int>) = Collections.checkedList(values, String::class.java)
        fun widened(values: MutableList<String>) = Collections.checkedList(values, Any::class.java)
        """)
        do { try runSema(context) } catch {}
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        let lines = Set(errors.compactMap { error in
            error.primaryRange.map { context.sourceManager.lineColumn(of: $0.start).line }
        })
        #expect(lines.isSuperset(of: [2, 3]), "\(errors)")
    }

    @Test
    func userDefinedJavaPackageFunctionKeepsKotlinArgumentRules() throws {
        try withTemporaryFile(contents: """
        package java.util
        object Collections {
            fun <T> checkedList(list: MutableList<T>, type: T): MutableList<T> = list
        }
        fun bad(values: List<Int>) = Collections.checkedList(values, 1)
        """) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false, allowDefaultStdlibLibrary: false)
            do { try runSema(context) } catch {}
            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 1 && errors[0].code == "KSWIFTK-TYPE-0001", "\(errors)")
        }
    }
}
