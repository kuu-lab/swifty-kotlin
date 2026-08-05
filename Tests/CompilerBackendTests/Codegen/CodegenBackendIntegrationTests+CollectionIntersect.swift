@testable import CompilerCore
@testable import CompilerBackend
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionIntersectTests {
    @Test
    func codegenListIntersectUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val result = listOf(1, 2, 2, 3, 4).intersect(listOf(2, 4, 5))
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "ListIntersectRuntime", emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains("kk_list_intersect"))
        }
    }
}
#endif
