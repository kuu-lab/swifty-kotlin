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
        #expect(property.initializer == nil, "The getter body must not become a property initializer")
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

    @Test
    func expressionGetterKeepsMemberGetCall() throws {
        // KUU-1363: `this.get()` inside an expression-bodied getter is a member
        // call, not a second accessor header. The body-extent scan must not
        // truncate the body at `get(` when the soft keyword follows `.`/`?.`/`::`.
        let (ast, ctx) = try buildASTModule(from: """
        class Box(val v: String) {
            fun get(): String = v
            val direct: String get() = this.get()
        }
        val Box.ext: String get() = this.get()
        val Box.nested: String get() = this.v.get(0).toString()
        """, includeStdlib: false)

        for (property, label) in [
            (try #require(memberProperty(named: "direct", ofClass: "Box", in: ast, interner: ctx.interner)), "direct"),
            (try #require(topLevelProperty(named: "ext", in: ast, interner: ctx.interner)), "ext"),
        ] {
            guard case let .expr(exprID, _) = property.getter?.body,
                  case let .memberCall(receiverID, callee, _, args, _) = ast.arena.expr(exprID),
                  case .thisRef = ast.arena.expr(receiverID)
            else {
                Issue.record("\(label) getter body must be the full this.get() member call")
                continue
            }
            #expect(ctx.interner.resolve(callee) == "get")
            #expect(args.isEmpty)
        }

        // A `get` call nested inside the body is not an accessor boundary either.
        let nested = try #require(topLevelProperty(named: "nested", in: ast, interner: ctx.interner))
        guard case let .expr(nestedID, _) = nested.getter?.body,
              case let .memberCall(_, nestedCallee, _, _, _) = ast.arena.expr(nestedID)
        else {
            Issue.record("nested getter body must keep the outermost member call")
            return
        }
        #expect(ctx.interner.resolve(nestedCallee) == "toString")
    }

    @Test
    func expressionGetterStillSplitsAtFollowingAccessorHeader() throws {
        let (ast, ctx) = try buildASTModule(from: """
        class C {
            var backing = 0
            var p: Int get() = backing + 1; set(v) { backing = v }
        }
        """, includeStdlib: false)
        let property = try #require(memberProperty(named: "p", ofClass: "C", in: ast, interner: ctx.interner))
        #expect(property.setter != nil)
        #expect(property.setter?.parameterName.map { ctx.interner.resolve($0) } == "v")
    }

    @Test
    func expressionSetterKeepsMemberSetCall() throws {
        let (ast, ctx) = try buildASTModule(from: """
        class Sink { fun set(v: Int) {} }
        class C {
            val sink = Sink()
            var p: Int set(v) = sink.set(v)
        }
        """, includeStdlib: false)
        let property = try #require(memberProperty(named: "p", ofClass: "C", in: ast, interner: ctx.interner))
        guard case let .expr(exprID, _) = property.setter?.body,
              case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID)
        else {
            Issue.record("Setter body must keep the sink.set(v) member call")
            return
        }
        #expect(ctx.interner.resolve(callee) == "set")
    }

    @Test(arguments: ["\n", " ", "; "])
    func expressionSetterPreservesElvisLambdaOrder(separator: String) throws {
        let (ast, ctx) = try buildASTModule(from: """
        class V<T : Any> {
            var stored: T? = null
            var flag = false
            var value: T? get() = stored\(separator)set(p) = p?.let { stored = it; flag = false } ?: run { flag = true }
        }
        """, includeStdlib: false)
        let property = try #require(memberProperty(named: "value", ofClass: "V", in: ast, interner: ctx.interner))
        guard case let .expr(exprID, _) = property.setter?.body,
              case let .binary(.elvis, lhsID, rhsID, _) = ast.arena.expr(exprID),
              case let .safeMemberCall(_, member, _, letArgs, _) = ast.arena.expr(lhsID),
              case let .call(calleeID, _, runArgs, _) = ast.arena.expr(rhsID),
              case let .nameRef(runName, _) = ast.arena.expr(calleeID)
        else {
            Issue.record("Expected a safe let call followed by an Elvis run call")
            return
        }
        #expect(ctx.interner.resolve(member) == "let")
        #expect(ctx.interner.resolve(runName) == "run")
        #expect(letArgs.count == 1)
        #expect(runArgs.count == 1)
        let letArg = try #require(letArgs.first)
        let runArg = try #require(runArgs.first)
        guard case let .lambdaLiteral(_, letBody, _, _) = ast.arena.expr(letArg.expr),
              case let .blockExpr(statements, trailing, _) = ast.arena.expr(letBody),
              case let .lambdaLiteral(_, runBody, _, _) = ast.arena.expr(runArg.expr),
              case let .blockExpr(runStatements, runTrailing, _) = ast.arena.expr(runBody)
        else {
            Issue.record("Both calls must retain their own lambda bodies")
            return
        }
        #expect(statements.count + (trailing == nil ? 0 : 1) == 2)
        #expect(runStatements.count + (runTrailing == nil ? 0 : 1) == 1)
    }
}
#endif
