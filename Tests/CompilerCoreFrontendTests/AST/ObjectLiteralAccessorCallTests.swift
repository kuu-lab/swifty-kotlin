#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite struct ObjectLiteralAccessorCallTests {
    private func firstObject(in ast: ASTModule) -> ObjectDecl? {
        for expression in ast.arena.exprs {
            guard case let .objectLiteral(_, declID, _) = expression,
                  let declID,
                  case let .objectDecl(declaration)? = ast.arena.decl(declID)
            else { continue }
            return declaration
        }
        return nil
    }

    @Test(arguments: [
        "get(1)", "set(2)", "get()", "set(value)",
        "get(1) + set(2)", "lookup.get(1)", "lookup?.set(2)",
        "(get(1))", "wrap(get(1))", "run { get(1) }",
        "get { 1 }", "get() { 1 }", "1 + get() { 2 }",
        "2 > get() { 1 }", "get(1) === get() { 1 }", "get(1) !== get() { 1 }",
        "if (true) get() { 1 } else 0", "1 choose get() { 2 }",
        "if (true) 1 else if (false) get() { 2 } else 3",
    ], [false, true])
    func callsAreNotAccessorHeaders(expression: String, annotated: Bool) throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun main() {
            val o = object {
                val value\(annotated ? ": Int" : "") = \(expression)
                val following = 3
            }
        }
        """, includeStdlib: false)
        let object = try #require(firstObject(in: ast))
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        #expect(object.memberProperties.count == 2)
        let id = try #require(object.memberProperties.first)
        guard case let .propertyDecl(property)? = ast.arena.decl(id) else {
            Issue.record("Expected an initialized property")
            return
        }
        #expect(property.initializer != nil)
        #expect(property.getter == nil)
        #expect(property.setter == nil)
    }

    @Test(arguments: ["\n", "; ", " "])
    func realAccessorsKeepCallsInTheirBodies(separator: String) throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun main() {
            val o = object {
                var value: Int get() = get(1)\(separator)set(v) { set(v) }
            }
        }
        """, includeStdlib: false)
        let object = try #require(firstObject(in: ast))
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let id = try #require(object.memberProperties.first)
        guard case let .propertyDecl(property)? = ast.arena.decl(id),
              case let .expr(expression, _) = property.getter?.body,
              case let .call(callee, _, _, _) = ast.arena.expr(expression),
              case let .nameRef(name, _) = ast.arena.expr(callee)
        else {
            Issue.record("Expected a getter returning get(1)")
            return
        }
        #expect(ctx.interner.resolve(name) == "get")
        #expect(property.initializer == nil)
        #expect(property.setter?.parameterName == ctx.interner.intern("v"))
        #expect(property.setter?.body != .unit)
    }

    @Test
    func genericTypeAndConditionalGetterKeepRealAccessors() throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun main() {
            val o = object {
                val values: List<Int> get() = source as List<Int>
                val softType: by get() = source
                var value: Int get() = if (true) 1 else if (false) get() { 2 } else 3
                    set(v) { set(v) }
            }
        }
        """, includeStdlib: false)
        let object = try #require(firstObject(in: ast))
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        #expect(object.memberProperties.count == 3)
        for id in object.memberProperties {
            guard case let .propertyDecl(property)? = ast.arena.decl(id) else {
                Issue.record("Expected an accessor property")
                continue
            }
            #expect(property.initializer == nil)
            #expect(property.getter != nil)
            #expect(property.getter?.body != .unit)
            if property.isVar {
                #expect(property.setter?.parameterName == ctx.interner.intern("v"))
            }
        }
    }

    @Test(arguments: ["++", "--"])
    func postfixInitializerKeepsFollowingAccessor(operation: String) throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun main() {
            var counter = 1
            val o = object {
                var value = counter\(operation) get() = field
                    set(v) { field = v }
            }
        }
        """, includeStdlib: false)
        let object = try #require(firstObject(in: ast))
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let id = try #require(object.memberProperties.first)
        guard case let .propertyDecl(property)? = ast.arena.decl(id) else {
            Issue.record("Expected an initialized accessor property")
            return
        }
        #expect(property.initializer != nil)
        #expect(property.getter != nil)
        #expect(property.setter?.parameterName == ctx.interner.intern("v"))
    }

    @Test(arguments: ["", ": Iface"])
    func initializerCallsRetainMembers(supertype: String) throws {
        let (_, ctx) = try buildASTModule(from: """
        interface Iface { fun f(): Int }
        fun get(x: Int): Int = x * 10
        fun set(x: Int): Int = x + 100
        fun main() {
            val o = object \(supertype) {
                val a = get(1)
                val b = set(2)
                \(supertype.isEmpty ? "" : "override ")fun f() = a + b
            }
            val result: Int = o.f()
        }
        """, includeStdlib: false)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let object = try #require(firstObject(in: ast))
        #expect(object.memberProperties.count == 2)
        #expect(object.memberFunctions.count == 1)
        for (id, name) in zip(object.memberProperties, ["get", "set"]) {
            guard case let .propertyDecl(property)? = ast.arena.decl(id),
                  let initializer = property.initializer,
                  case let .call(callee, _, arguments, _) = ast.arena.expr(initializer),
                  case let .nameRef(calleeName, _) = ast.arena.expr(callee)
            else {
                Issue.record("Expected a stored property initialized by a call to \(name)")
                continue
            }
            #expect(ctx.interner.resolve(calleeName) == name)
            #expect(arguments.count == 1)
            #expect(property.getter == nil)
            #expect(property.setter == nil)
        }
    }
}
#endif
