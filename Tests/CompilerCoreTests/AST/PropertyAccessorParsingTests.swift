#if canImport(Testing)
@testable import CompilerCore
import Testing

/// Regression coverage for inline property accessors that are split by a
/// semicolon in the CST: the first accessor can stay on the property node while
/// the next accessor is wrapped in a `.propertyAccessor` child.
@Suite
struct PropertyAccessorParsingTests {
    @Test
    func semicolonSeparatedGetterAndSetterAreBothParsed() throws {
        let (ast, ctx) = try buildASTModule(from: """
        class T {
            var c = 0
            var f: Int get() = c * 2; set(v) { c = v / 2 }
        }
        """, includeStdlib: false)

        let property = try #require(memberProperty(named: "f", ofClass: "T", in: ast, interner: ctx.interner))
        #expect(property.isVar)
        #expect(property.getter != nil, "The inline getter must not be lost when the setter is a child node")
        #expect(property.setter != nil)
        #expect(property.getter?.body != .unit)
        #expect(property.setter?.body != .unit)
    }

    @Test
    func inlineBlockGetterRetainsItsBody() throws {
        let (ast, ctx) = try buildASTModule(from: """
        class C(val p: String) {
            val c: String get() { return p }
        }
        """, includeStdlib: false)
        let property = try #require(memberProperty(named: "c", ofClass: "C", in: ast, interner: ctx.interner))
        guard case let .block(statements, _) = property.getter?.body else {
            Issue.record("Inline block getter must retain its body")
            return
        }
        #expect(statements.count == 1)
    }

    @Test
    func expressionGetterRetainsTrailingLambdaCall() throws {
        let (ast, ctx) = try buildASTModule(from: """
        class C(val p: String) {
            val c: List<String> get() = p.split("/").filter { it.isNotEmpty() }
        }
        """, includeStdlib: false)
        let property = try #require(memberProperty(named: "c", ofClass: "C", in: ast, interner: ctx.interner))
        guard case let .expr(exprID, _) = property.getter?.body else {
            Issue.record("Trailing lambda must belong to the getter expression")
            return
        }
        #expect(ast.arena.expr(exprID) != nil)
    }
}
#endif
