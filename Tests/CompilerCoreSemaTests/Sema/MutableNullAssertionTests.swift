#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct MutableNullAssertionTests {
    private let declarations = """
    class Node(val value: Int, val next: Node?) {
        fun run(n: Node): Int = n.value
    }
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
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0473" }, "\(errors)")
    }

    // KUU-3943: `x!!` inside an `&&`/`||` operand narrows on every branch where
    // it was actually evaluated. The then-body of `cond && x!!.prop` proves
    // `x` non-null because reaching it required evaluating the `!!`.
    @Test(arguments: [
        // `x!!` on the right of `&&`: narrowed inside the then-body.
        "var node = head; if (flag) { node = Node(1, null) }; if (flag && node!!.value > 0) { return read(node) }; return 0",
        // `x!!` on the right of `||`: narrowed inside the else-body.
        "var node = head; if (flag) { node = Node(1, null) }; if (flag || node!!.value > 0) { return 0 } else { return read(node) }",
        // `x!!` on the left of `&&` always runs: narrowed in both bodies.
        "var node = head; if (flag) { node = Node(1, null) }; if (node!!.value > 0 && flag) { return read(node) } else { return read(node) }",
        // `x!!` as a call argument on the right of `&&`.
        "var node = head; if (flag) { node = Node(1, null) }; if (flag && read(node!!) > 0) { return read(node) }; return 0",
        // `x!!` on the left of `||` always runs: narrowed after the if too.
        "var node = head; if (flag) { node = Node(1, null) }; if (node!!.value > 0 || flag) { }; return read(node)",
        // `&&` RHS `!!` narrows the while-body the same way.
        "var node = head; if (flag) { node = Node(1, null) }; var i = 0; while (flag && node!!.value > 0 && i < 1) { i += read(node) }; return i",
        // Subjectless when conditions take the same branchOnCondition path.
        "var node = head; if (flag) { node = Node(1, null) }; return when { flag && node!!.value > 0 -> read(node); else -> 0 }"
    ])
    func narrowsEvaluatedNullAssertThroughCompositeCondition(body: String) throws {
        let context = makeContext(declarations + "\nfun check(head: Node?, flag: Boolean): Int {\n" + body + "\n}")
        try runSema(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        // `&&` else-body: the `x!!` did not run on the `flag == false` path.
        "var node = head; if (flag) { node = Node(1, null) }; if (flag && node!!.value > 0) { } else { return read(node) }; return 0",
        // `||` then-body: merges paths that did and did not evaluate `x!!`.
        "var node = head; if (flag) { node = Node(1, null) }; if (flag || node!!.value > 0) { return read(node) }; return 0",
        // A stored `&&` result leaves a path where `x!!` never ran.
        "var node = head; if (flag) { node = Node(1, null) }; val b = flag && node!!.value > 0; return read(node)",
        // `x!!` inside a safe-call argument evaluates only on the non-null path.
        "var node = head; var box: Node? = Node(1, null); if (flag) { node = Node(1, null) }; if (box?.run(node!!) == 1) { } else { return read(node) }; return 0"
    ])
    func rejectsNullAssertNarrowingOnUnevaluatedPaths(body: String) throws {
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
