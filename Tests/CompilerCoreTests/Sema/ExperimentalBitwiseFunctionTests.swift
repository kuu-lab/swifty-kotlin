#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ExperimentalBitwiseFunctionTests {
    @Test func testByteAndShortBitwiseFunctionsResolveThroughKotlinExperimentalImports() throws {
        let source = """
        import kotlin.experimental.and
        import kotlin.experimental.inv
        import kotlin.experimental.or
        import kotlin.experimental.xor

        fun byteOps(a: Byte, b: Byte) {
            a.and(b)
            a.inv()
            a.or(b)
            a.xor(b)
        }

        fun shortOps(a: Short, b: Short) {
            a.and(b)
            a.inv()
            a.or(b)
            a.xor(b)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let diagnosticsEmpty = ctx.diagnostics.diagnostics.isEmpty
        #expect(
            diagnosticsEmpty,
            "Expected kotlin.experimental Byte/Short bitwise imports to resolve cleanly, got \(ctx.diagnostics.diagnostics)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let userFileID = try #require(ast.files.first { file in
            !ctx.sourceManager.path(of: file.fileID).hasPrefix("__bundled_")
        }?.fileID)
        let bitwiseNames: Set<String> = ["and", "inv", "or", "xor"]
        var seenCalls: [String: Int] = [:]

        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(exprID), range.start.file == userFileID else {
                continue
            }
            guard case let .memberCall(receiver, callee, _, args, _) = ast.arena.expr(exprID) else {
                continue
            }
            let name = ctx.interner.resolve(callee)
            guard bitwiseNames.contains(name) else {
                continue
            }

            seenCalls[name, default: 0] += 1
            #expect(sema.bindings.exprTypes[receiver] == sema.types.intType)
            #expect(sema.bindings.exprTypes[exprID] == sema.types.intType)
            for arg in args {
                #expect(sema.bindings.exprTypes[arg.expr] == sema.types.intType)
            }
        }

        #expect(seenCalls == ["and": 2, "inv": 2, "or": 2, "xor": 2])
    }
}
#endif
