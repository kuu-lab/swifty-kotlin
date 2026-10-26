@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct IndexedAssignExtensionScopeTests {
    @Test
    func unrelatedArraySetFallsThroughToDefaultImportedMapSet() throws {
        let ctx = makeContextFromSource("""
        data class Point(val x:Int,val y:Int)
        operator fun Array<CharArray>.set(at:Point,c:Char){this[at.y][at.x]=c}
        fun main(){val values=mutableMapOf<Point,Int>();values[Point(0,0)]=1;println(values.values)}
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let (sema, callee) = try mapSetter(in: ctx)
        let symbol = try #require(sema.symbols.symbol(callee))
        #expect(symbol.fqName.map(ctx.interner.resolve) == ["kotlin", "collections", "set"])
        #expect(sema.symbols.isSourceBackedSymbol(callee))
        #expect(!symbol.flags.contains(.synthetic))
    }

    @Test
    func applicableUserExtensionKeepsPriorityOverDefaultImport() throws {
        let ctx = makeContextFromSource("""
        data class Point(val x: Int, val y: Int)
        operator fun MutableMap<Point, Int>.set(at: Point, value: Int) { put(at, value + 1) }
        fun main() { val values = mutableMapOf<Point, Int>(); values[Point(0, 0)] = 1 }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let (sema, callee) = try mapSetter(in: ctx)
        let file = try #require(sema.symbols.sourceFileID(for: callee))
        #expect(ctx.sourceManager.origin(of: file) == .user)
    }

    @Test
    func compoundAssignmentBindsTopLevelMutableMapSetExtension() throws {
        let ctx = makeContextFromSource("""
        operator fun <K, V> MutableMap<K, V>.set(key: K, value: V) = put(key, value)
        fun main() {
            val commands: MutableMap<String, String> = HashMap()
            commands["c1"] = "239"
            commands["c1"] += "932"
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        let (sema, callee) = try compoundMapSetter(in: ctx)
        let file = try #require(sema.symbols.sourceFileID(for: callee))
        #expect(ctx.sourceManager.origin(of: file) == .user)
    }

    @Test
    func compoundAssignmentKeepsApplicableMemberSetAheadOfExtension() throws {
        let ctx = makeContextFromSource("""
        class Bucket {
            operator fun get(index: Int): String = "239"
            operator fun set(index: Int, value: String) {}
        }
        operator fun Bucket.set(index: Int, value: String) {}
        fun use(bucket: Bucket) { bucket[0] += "932" }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let assignment = try compoundAssignment(in: ctx, receiverName: "bucket")
        let binding = try #require(sema.bindings.indexedCompoundAssignOperatorBinding(for: assignment))
        let owner = try #require(sema.symbols.parentSymbol(for: binding.setCall.chosenCallee))
        #expect(sema.symbols.symbol(owner)?.name == ctx.interner.intern("Bucket"))
    }

    @Test
    func compoundAssignmentDoesNotUsePrivateSetterFromAnotherFile() throws {
        let declaration = """
        private operator fun <K, V> MutableMap<K, V>.set(key: K, value: V) = put(key, value)
        """
        let usage = """
        fun main() {
            val commands: MutableMap<String, String> = mutableMapOf()
            commands["c1"] += "932"
        }
        """
        try withTemporaryFile(contents: declaration) { privatePath in
            try withTemporaryFile(contents: usage) { usagePath in
                let ctx = makeCompilationContext(inputs: [privatePath, usagePath])
                try runSema(ctx)
                #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

                let (sema, callee) = try compoundMapSetter(in: ctx)
                let privateFile = try #require(ctx.sourceManager.fileID(forPath: privatePath))
                let selectedFile = try #require(sema.symbols.sourceFileID(for: callee))
                #expect(selectedFile != privateFile)
                #expect(ctx.sourceManager.origin(of: selectedFile) == .bundledStdlib)
            }
        }
    }

    @Test
    func compoundAssignmentRejectsSetExtensionsWithIncompatibleArguments() throws {
        let ctx = makeContextFromSource("""
        class Box { operator fun get(index: Int): String = "value" }
        class Other
        operator fun Box.set(index: Long, value: String) {}
        operator fun Other.set(index: Int, value: String) {}
        fun use(box: Box, index: Int) { box[index] += "!" }
        """)
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
        let sema = try #require(ctx.sema)
        let assignment = try compoundAssignment(in: ctx, receiverName: "box")
        #expect(sema.bindings.indexedCompoundAssignOperatorBinding(for: assignment) == nil)
    }

    @Test(arguments: ["values[1] = 1", "values[Point(0, 0)] = 'x'"])
    func unrelatedArraySetDoesNotAcceptWrongMapKeyOrValue(assignment: String) throws {
        let ctx = makeContextFromSource("""
        data class Point(val x: Int, val y: Int)
        operator fun Array<CharArray>.set(at: Point, c: Char) { this[at.y][at.x] = c }
        fun main() { val values = mutableMapOf<Point, Int>(); \(assignment) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Expected invalid map assignment to be rejected")
    }

    private func mapSetter(in ctx: CompilationContext) throws -> (SemaModule, SymbolID) {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let assignment = try #require(firstExprID(in: ast) { _, expr in
            guard case let .indexedAssign(receiver, _, _, range) = expr,
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  case let .nameRef(name, _) = ast.arena.expr(receiver)
            else { return false }
            return ctx.interner.resolve(name) == "values"
        })
        let callee = try #require(sema.bindings.callBinding(for: assignment)?.chosenCallee)
        return (sema, callee)
    }

    private func compoundMapSetter(in ctx: CompilationContext) throws -> (SemaModule, SymbolID) {
        let sema = try #require(ctx.sema)
        let assignment = try compoundAssignment(in: ctx, receiverName: "commands")
        let binding = try #require(sema.bindings.indexedCompoundAssignOperatorBinding(for: assignment))
        return (sema, binding.setCall.chosenCallee)
    }

    private func compoundAssignment(in ctx: CompilationContext, receiverName: String) throws -> ExprID {
        let ast = try #require(ctx.ast)
        return try #require(firstExprID(in: ast) { _, expr in
            guard case let .indexedCompoundAssign(_, receiver, _, _, range) = expr,
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  case let .nameRef(name, _) = ast.arena.expr(receiver)
            else { return false }
            return ctx.interner.resolve(name) == receiverName
        })
    }
}
