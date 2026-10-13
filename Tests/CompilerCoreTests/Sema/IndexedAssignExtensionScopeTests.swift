@testable import CompilerCore
import Testing

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
}
