@testable import CompilerCore
import Testing

@Suite
struct PrimitiveArrayPlusTests {
    @Test func allPrimitiveArrayPlusOverloadsResolve() throws {
        let source = ["Byte", "Short", "Int", "Long", "Float", "Double", "Char", "Boolean"].map { type in
            """
            fun plus\(type)(array: \(type)Array, element: \(type), other: \(type)Array, collection: Collection<\(type)>): \(type)Array {
                val withElement: \(type)Array = array + element
                val withArray: \(type)Array = array + other
                val withCollection: \(type)Array = array + collection
                val explicitElement: \(type)Array = array.plus(element)
                val explicitArray: \(type)Array = array.plus(other)
                val explicitCollection: \(type)Array = array.plus(collection)
                return withElement
            }
            """
        }.joined(separator: "\n")
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected all primitive array plus overloads to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
