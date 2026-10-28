#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// Annotated properties in anonymous object bodies must survive the
/// object-literal member parser as ordinary property declarations.
///
/// See `Scripts/diff_cases/annotated_object_literal_property.kt` and the pinned
/// Kotlin test `AnnotatedLocalObjectProperty.kt` at commit
/// `679366a83f99851b42f64795f10ed803ff011c73`.
@Suite
struct ObjectLiteralAnnotatedPropertyTests {
    private func objectLiteralProperties(_ source: String) throws -> [(String, PropertyDecl)] {
        let fakePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let context = makeCompilationContext(inputs: [fakePath], includeStdlib: false)
        _ = context.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
        try runFrontend(context)
        let ast = try #require(context.ast)

        return ast.arena.exprs.flatMap { expression -> [(String, PropertyDecl)] in
            guard case let .objectLiteral(_, declID, _) = expression,
                  let declID,
                  case let .objectDecl(objectDecl)? = ast.arena.decl(declID)
            else {
                return []
            }
            return objectDecl.memberProperties.compactMap { propertyID in
                guard case let .propertyDecl(property)? = ast.arena.decl(propertyID) else {
                    return nil
                }
                return (context.interner.resolve(property.name), property)
            }
        }
    }

    @Test
    func annotatedPropertiesAreRegisteredWithTheirAnnotations() throws {
        let properties = try objectLiteralProperties("""
        annotation class My
        fun foo(): Int {
            val explicit = object { @My val bar: Int = 0 }
            val inferred = object { @My val bar = 1 }
            return explicit.bar + inferred.bar
        }
        """)
        let bars = properties.filter { $0.0 == "bar" }.map(\.1)

        #expect(bars.count == 2, "expected both annotated object-literal properties in the AST")
        #expect(bars.allSatisfy { $0.annotations.map(\.name) == ["My"] })
        #expect(bars.allSatisfy { $0.initializer != nil })
        #expect(bars.filter { $0.type != nil }.count == 1)
        #expect(bars.filter { $0.type == nil }.count == 1)
    }
}
#endif
