@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite(.serialized)
struct CodegenBackendCollectionIsNullOrEmptyTests {
    @Test
    func testCodegenNullableCollectionsIsNullOrEmptyUsesIsEmptyHelpers() throws {
        let source = """
        fun main() {
            val nullableList: List<Int>? = null
            val nullableSet: Set<Int>? = null
            val nullableMap: Map<String, Int>? = null
            val nullableArray: Array<Int>? = null
            println(nullableList.isNullOrEmpty())
            println(nullableSet.isNullOrEmpty())
            println(nullableMap.isNullOrEmpty())
            println(nullableArray.isNullOrEmpty())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            #expect(throwFlags["kk_list_is_empty"]?.allSatisfy { $0 == false } == true)
            #expect(throwFlags["__kk_set_is_empty"]?.allSatisfy { $0 == false } == true)
            #expect(throwFlags["kk_map_is_empty"]?.allSatisfy { $0 == false } == true)
            #expect(throwFlags["kk_array_is_empty"]?.allSatisfy { $0 == false } == true)
        }
    }
}
#endif
