#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct MutableNullAssertionTests {
    private let declarations = """
    class Node(val value: Int, val next: Node?)
    fun read(node: Node): Int = node.value
    fun next(node: Node): Node? = node.next
    """

    @Test(arguments: [
        """
        var node = head
        var total = 0
        do {
            node!!
            total += read(node)
            node = next(node)
        } while (node != null)
        return total
        """,
        """
        val action = {
            var node = head
            var total = 0
            do {
                node!!
                total += read(node)
                node = next(node)
            } while (node != null)
            total
        }
        return action()
        """,
        """
        var node = head
        node!!
        val result = read(node)
        node = null
        return result
        """,
        """
        val node = head
        node!!
        return read(node)
        """
    ])
    func narrowsSequencedLocalAfterAssertion(body: String) throws {
        let context = makeContext(declarations + "\nfun check(head: Node?): Int {\n" + body + "\n}")
        try runSema(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let sema = try #require(context.sema)
        let calls = sema.bindings.callBindings.values.filter { binding in
            guard let function = sema.symbols.symbol(binding.chosenCallee) else { return false }
            return context.interner.resolve(function.name) == "read"
        }
        #expect(!calls.isEmpty)
    }

    @Test(arguments: [
        "var node = head; node!!; node = null; return read(node)",
        "var node = head; val mutate = { node = null }; node!!; val result = read(node); mutate(); return result",
        "var node = head; if (flag) { node!! }; return read(node)",
        "var node = head; do { node!!; node = next(node) } while (flag); return read(node)"
    ])
    func rejectsInvalidatedOrDeferredNarrowing(body: String) throws {
        let context = makeContext(declarations + "\nfun check(head: Node?, flag: Boolean): Int {\n" + body + "\n}")
        try runSema(context)
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0002" }, "\(errors)")
    }

    private func makeContext(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let context = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = context.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return context
    }
}
#endif
