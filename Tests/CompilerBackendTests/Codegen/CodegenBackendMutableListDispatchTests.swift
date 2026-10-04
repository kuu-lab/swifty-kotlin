@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendMutableListDispatchTests {
    @Test(arguments: [true, false])
    func arrayListRemoveRejectsFrozenMissingAndPresentElements(artifact: Bool) throws {
        try assertKotlinOutput(
            """
            @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
            fun element(): String {
                println("evaluated")
                return "missing"
            }
            fun main() {
                val list = ArrayList<String>()
                list.add("hello")
                list.add("hello")
                println(list.remove("missing"))
                println(list.remove("hello"))
                println(list)
                val built = list.build()
                try { list.remove(element()); println("accepted-missing") }
                catch (e: IllegalArgumentException) { println("wrong-exception") }
                catch (e: UnsupportedOperationException) { println("rejected-missing") }
                finally { println("finally") }
                try { list.remove("hello"); println("accepted-present") }
                catch (e: UnsupportedOperationException) { println("rejected-present") }
                val widened: MutableList<String> = list
                try { widened.remove("missing"); println("accepted-widened") }
                catch (e: UnsupportedOperationException) { println("rejected-widened") }
                val nullable: ArrayList<String>? = list
                try { nullable?.remove("missing"); println("accepted-safe") }
                catch (e: UnsupportedOperationException) { println("rejected-safe") }
                println(list)
                println(built)
                val empty = ArrayList<String>()
                empty.build()
                try { empty.remove("missing"); println("accepted-empty") }
                catch (e: UnsupportedOperationException) { println("rejected-empty") }
                println(empty.size)
                val nulls = ArrayList<String?>()
                nulls.add(null)
                nulls.build()
                try { nulls.remove(null); println("accepted-null") }
                catch (e: UnsupportedOperationException) { println("rejected-null") }
                println(nulls.size)
            }
            """,
            moduleName: "ArrayListFrozenRemove",
            expected: "false\ntrue\n[hello]\nevaluated\nrejected-missing\nfinally\nrejected-present\nrejected-widened\nrejected-safe\n[hello]\n[hello]\nrejected-empty\n0\nrejected-null\n1\n",
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [true, false])
    func mutableListRemovePropagatesOverrideException(artifact: Bool) throws {
        try assertKotlinOutput(
            """
            class RejectingList : AbstractMutableList<Int>() {
                override val size: Int get() = 0
                override fun get(index: Int): Int = throw IndexOutOfBoundsException()
                override fun set(index: Int, element: Int): Int = throw IndexOutOfBoundsException()
                override fun add(index: Int, element: Int) { throw IndexOutOfBoundsException() }
                override fun removeAt(index: Int): Int = throw IndexOutOfBoundsException()
                override fun remove(element: Int): Boolean { throw IllegalStateException("remove-override") }
            }
            fun main() {
                val list: MutableList<Int> = RejectingList()
                try { list.remove(1); println("accepted") }
                catch (e: IllegalStateException) { println(e.message) }
            }
            """,
            moduleName: "MutableListThrowingRemove",
            expected: "remove-override\n",
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [true, false])
    func mutationsDispatchThroughMutableList(artifact: Bool) throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 { root.deleteLastPathComponent() }
        let source = try String(contentsOf: root.appendingPathComponent(
            "Scripts/diff_cases/ksp1072_custom_mutable_list.kt"
        ), encoding: .utf8)
        try assertKotlinOutput(
            source,
            moduleName: "MutableListDispatch",
            expected: "1\ntrue\ntrue\nfalse\ntrue\nfalse\n9\ntrue\nfalse\ntrue\nfalse\ntrue\nfalse\n[10, 8, 5, 6]\n10\n8\n5\n[80, 50, 55, 6]\naddAt-oob\naddAllAt-oob\nremoveAt-override\n55\n[]\nsaiAABBdrrRRTTjlLuiBddc\ntrue\ntrue\n[80]\ntrue\nfalse\n[1, 2]\n",
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [true, false])
    func concreteArrayListRemoveKeepsSourceThrowingChannel(artifact: Bool) throws {
        let source = """
        fun main() {
            val array = ArrayList<Int>()
            try { array.remove(1); println("bypassed") }
            catch (e: IllegalStateException) { println(e.message) }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx: CompilationContext
            if artifact {
                let library = makeCompilationContext(
                    inputs: [], moduleName: "KSwiftKStdlib", emit: .library,
                    outputPath: output + "-stdlib", stdlibOnly: true,
                    allowDefaultStdlibLibrary: false
                )
                try loadArrayListWithThrowingRemove(library)
                try compileLoadedSources(library)
                ctx = makeCompilationContext(
                    inputs: [path], emit: .executable, outputPath: output,
                    stdlibLibraryPath: output + "-stdlib.kklib",
                    allowDefaultStdlibLibrary: false
                )
                try runToKIR(ctx)
                try LoweringPhase().run(ctx)
                try CodegenPhase().run(ctx)
            } else {
                ctx = makeCompilationContext(
                    inputs: [path], emit: .executable, outputPath: output,
                    allowDefaultStdlibLibrary: false
                )
                try loadArrayListWithThrowingRemove(ctx)
                try compileLoadedSources(ctx)
            }
            #expect(!ctx.diagnostics.hasError)
            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            var checked = false
            for (index, expr) in ast.arena.exprs.enumerated() {
                guard case .memberCall = expr else { continue }
                let id = ExprID(rawValue: Int32(index))
                guard let range = ast.arena.exprRange(id),
                      ctx.sourceManager.slice(range) == "array.remove(1)"
                else { continue }
                let binding = try #require(sema.bindings.callBinding(for: id))
                let callee = try #require(sema.symbols.symbol(binding.chosenCallee))
                #expect(callee.fqName.map(ctx.interner.resolve) == ["kotlin", "collections", "ArrayList", "remove"])
                #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) != "__kk_mutable_collection_remove")
                checked = true
            }
            #expect(checked)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.stdout == "arraylist-remove\n")
        }
    }

    private func loadArrayListWithThrowingRemove(_ ctx: CompilationContext) throws {
        try LoadSourcesPhase().run(ctx)
        let path = "__bundled_kotlin/collections/ArrayList/ArrayList.kt"
        let file = try #require(ctx.sourceManager.fileID(forPath: path))
        var source = String(decoding: ctx.sourceManager.contents(of: file), as: UTF8.self)
        // Model the source guard prerequisite without implementing ArrayList.build guards.
        let external = "override external fun remove(element: E): Boolean"
        let signature = "override fun remove(element: E): Boolean"
        let declaration = try #require(source.range(of: external) ?? source.range(of: signature))
        var end = declaration.upperBound
        if !source[declaration].contains("external") {
            let open = try #require(source[end...].firstIndex(of: "{"))
            var depth = 1
            end = source.index(after: open)
            while depth > 0, end < source.endIndex {
                if source[end] == "{" { depth += 1 }
                if source[end] == "}" { depth -= 1 }
                end = source.index(after: end)
            }
            #expect(depth == 0)
        }
        source.replaceSubrange(declaration.lowerBound ..< end, with:
            signature + " { throw IllegalStateException(\"arraylist-remove\") }"
        )
        let method = try #require(source.range(of: signature))
        let annotation = "@KsSymbolName(\"__kk_mutable_list_remove\")"
        if let link = source[..<method.lowerBound].range(of: annotation, options: .backwards),
           source[link.upperBound ..< method.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            source.removeSubrange(link)
        }
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8), origin: .bundledStdlib)
    }

    private func compileLoadedSources(_ ctx: CompilationContext) throws {
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPhase().run(ctx)
        try BuildKIRPhase().run(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)
    }
}
