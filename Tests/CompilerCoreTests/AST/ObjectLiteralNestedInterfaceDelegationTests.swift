#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite struct ObjectLiteralNestedInterfaceDelegationTests {
    @Test(arguments: ["val inner", "var inner", "val inner: Iface"])
    func nestedInterfaceDelegateRemainsInPropertyInitializer(_ propertyHeader: String) throws {
        let source = """
        interface Iface { fun f(): Int }
        class Impl : Iface { override fun f() = 1 }
        fun main() {
            val o = object {
                \(propertyHeader) = object : Iface by Impl() { }
                fun g() = inner.f()
            }
            println(o.g())
        }
        """
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runFrontend(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let outerDecls = ast.arena.exprs.compactMap { expr -> ObjectDecl? in
            guard case let .objectLiteral(_, declID, _) = expr,
                  let declID,
                  case let .objectDecl(decl)? = ast.arena.decl(declID),
                  !decl.memberProperties.isEmpty
            else { return nil }
            return decl
        }
        let outer = try #require(outerDecls.first)
        #expect(outer.memberProperties.count == 1)
        #expect(outer.memberFunctions.count == 1)
        let propertyID = try #require(outer.memberProperties.first)
        guard case let .propertyDecl(property)? = ast.arena.decl(propertyID) else {
            Issue.record("Expected the inner member property")
            return
        }
        #expect(property.delegateExpression == nil)
        let initializer = try #require(property.initializer)
        guard case let .objectLiteral(_, innerDeclID, _)? = ast.arena.expr(initializer),
              let innerDeclID,
              case let .objectDecl(inner)? = ast.arena.decl(innerDeclID)
        else {
            Issue.record("Expected an object literal initializer")
            return
        }
        #expect(inner.superTypeEntries.compactMap(\.delegateExpression).count == 1)
    }
}
#endif
