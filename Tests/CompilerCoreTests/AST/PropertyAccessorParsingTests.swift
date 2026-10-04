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
    func sameLineBlockGetterAndSetterKeepTypeAndBodies() throws {
        let (ast, ctx) = try buildASTModule(from: """
        class C {
            var backing = 0
            var p: Int get() { println("get"); return backing } set(v) { println("set"); backing = v }
        }
        """, includeStdlib: false)
        let property = try #require(memberProperty(named: "p", ofClass: "C", in: ast, interner: ctx.interner))
        // The getter header must not leak into the type annotation (`Int get()`).
        let typeRef = try #require(property.type.flatMap { ast.arena.typeRef($0) })
        guard case let .named(path, args, nullable) = typeRef else {
            Issue.record("Expected a plain named type, got \(typeRef)")
            return
        }
        #expect(path.map { ctx.interner.resolve($0) } == ["Int"])
        #expect(args.isEmpty)
        #expect(!nullable)
        guard case let .block(getterStatements, _) = property.getter?.body,
              case let .block(setterStatements, _) = property.setter?.body
        else {
            Issue.record("Both same-line accessors must keep their block bodies")
            return
        }
        #expect(getterStatements.count == 2)
        #expect(setterStatements.count == 2, "The setter's assignment must not be dropped")
    }

    @Test
    func sameLineSetterBeforeGetterIsParsed() throws {
        let (ast, ctx) = try buildASTModule(from: """
        class C {
            var backing = 0
            var q: Int set(v) { backing = v * 10 } get() { return backing }
        }
        """, includeStdlib: false)
        let property = try #require(memberProperty(named: "q", ofClass: "C", in: ast, interner: ctx.interner))
        #expect(property.getter != nil)
        #expect(property.setter != nil)
        #expect(property.setter?.parameterName.map { ctx.interner.resolve($0) } == "v")
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
