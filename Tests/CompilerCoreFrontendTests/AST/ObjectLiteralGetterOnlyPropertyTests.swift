#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct ObjectLiteralGetterOnlyPropertyTests {
    private func objectLiteralProperties(_ source: String) throws -> [(name: String, decl: PropertyDecl)] {
        let fakePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [fakePath], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
        try runFrontend(ctx)
        let ast = try #require(ctx.ast)
        var result: [(String, PropertyDecl)] = []
        for expr in ast.arena.exprs {
            guard case let .objectLiteral(_, declID, _) = expr,
                  let declID,
                  case let .objectDecl(objectDecl)? = ast.arena.decl(declID)
            else { continue }
            for propID in objectDecl.memberProperties {
                if case let .propertyDecl(prop)? = ast.arena.decl(propID) {
                    result.append((ctx.interner.resolve(prop.name), prop))
                }
            }
        }
        return result
    }

    @Test func getterOnlyPropertyWithInferredTypeKeepsGetterBody() throws {
        let props = try objectLiteralProperties("""
        interface Counter { val name: String }
        fun main() {
            val a = object : Counter { var v = 0; override val name get() = "m$v" }
            val b = object { var v = 0; val name get() = "p$v" }
            val c = object {
                var raw = 1
                var x get() = raw * 10
                    set(value) { raw = value }
            }
        }
        """)
        for name in ["name", "x"] {
            let matches = props.filter { $0.name == name }
            #expect(!matches.isEmpty)
            for match in matches {
                #expect(match.decl.initializer == nil, "getter body must not become the initializer of \(name)")
                #expect(match.decl.getter != nil)
            }
        }
        #expect(props.first { $0.name == "x" }?.decl.setter != nil)
        let plain = try objectLiteralProperties("fun main() { val o = object { val k = 1 } }")
        #expect(plain.first { $0.name == "k" }?.decl.initializer != nil)
    }
}
#endif
