@testable import CompilerCore
import Foundation
import Testing

@Suite
struct PrimaryConstructorVisibilityTests {
    @Test
    func constructorPropertyModifiersRoundTripAndDecodeOlderAST() throws {
        let parameter = ValueParamDecl(
            name: InternedString(rawValue: 1), type: nil, isProperty: true,
            propertyVisibilityModifiers: [.private]
        )
        let data = try JSONEncoder().encode(parameter)
        #expect(try JSONDecoder().decode(ValueParamDecl.self, from: data) == parameter)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "propertyVisibilityModifiers")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(ValueParamDecl.self, from: legacy)
        #expect(decoded.propertyVisibilityModifiers == nil)
        #expect(decoded.isProperty)
    }

    @Test
    func privateConstructorPropertyAllowsContravariantParameter() throws {
        try withTemporaryFiles(contents: ["class Sink<in T>(private val value: T)"]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: ["private", "protected"])
    func constructorPropertyIsNotAccessibleOutsideOwner(visibility: String) throws {
        let source = """
        open class Owner(\(visibility) val value: Int)
        fun reveal(owner: Owner): Int = owner.value
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
            let expectedCode = visibility == "private" ? "KSWIFTK-SEMA-0040" : "KSWIFTK-SEMA-0041"
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == expectedCode })
        }
    }
}
