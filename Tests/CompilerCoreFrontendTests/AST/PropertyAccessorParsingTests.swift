#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// Regression coverage for inline property accessors that are split by a
/// semicolon in the CST: the first accessor can stay on the property node while
/// the next accessor is wrapped in a `.propertyAccessor` child.
@Suite
struct PropertyAccessorParsingTests {
    @Test(arguments: ["=", "by lazy"])
    func initializerObjectAccessorsStayOnTheObject(_ initializer: String) throws {
        let (ast, ctx) = try buildASTModule(from: """
        val completion \(initializer) {
            val nested = object {
                var context: Int get() = 42
                    set(value) {}
            }
            nested
        }
        """, includeStdlib: false)
        let property = try #require(topLevelProperty(named: "completion", in: ast, interner: ctx.interner))
        #expect(property.getter == nil)
        #expect(property.setter == nil)
        let objects = ast.arena.exprs.compactMap { expression -> ObjectDecl? in
            guard case let .objectLiteral(_, declID?, _) = expression,
                  case let .objectDecl(object)? = ast.arena.decl(declID) else { return nil }
            return object
        }
        let object = try #require(objects.first)
        let member = try #require(object.memberProperties.first.flatMap { ast.arena.decl($0) })
        guard case let .propertyDecl(nested) = member else {
            Issue.record("Expected the object's context property")
            return
        }
        #expect(nested.getter != nil)
        #expect(nested.setter != nil)
    }

    @Test
    func objectInitializerDoesNotSupplyTheOuterGetter() throws {
        let (ast, ctx) = try buildASTModule(from: """
        val completion = object {
            val context: Int get() = 42
        }
        """, includeStdlib: false)
        let property = try #require(topLevelProperty(named: "completion", in: ast, interner: ctx.interner))
        #expect(property.initializer != nil)
        #expect(property.getter == nil)
        #expect(property.setter == nil)
    }

    @Test
    func objectInitializerPreservesAnExplicitOuterGetter() throws {
        let (ast, ctx) = try buildASTModule(from: """
        val completion = object {
            val context: Int get() = 42
        }
            get() = field
        """, includeStdlib: false)
        let property = try #require(topLevelProperty(named: "completion", in: ast, interner: ctx.interner))
        #expect(property.initializer != nil)
        guard case let .expr(body, _) = property.getter?.body,
              case let .nameRef(name, _) = ast.arena.expr(body) else {
            Issue.record("The outer property's explicit getter must be retained")
            return
        }
        #expect(ctx.interner.resolve(name) == "field")
        #expect(property.setter == nil)
    }

    @Test(arguments: ["(Int) -> Int", "String.(Int) -> Int"])
    func inlineExpressionGetterRetainsFunctionTypeBeforeLambda(_ type: String) throws {
        let (ast, ctx) = try buildASTModule(from: """
        class Holder {
            val callback: \(type) get() = { it }
        }
        """, includeStdlib: false)
        let property = try #require(memberProperty(named: "callback", ofClass: "Holder", in: ast, interner: ctx.interner))
        let typeRef = try #require(property.type.flatMap { ast.arena.typeRef($0) })
        guard case let .functionType(_, receiver, parameters, _, _, _) = typeRef else {
            Issue.record("Expected a function property annotation, got \(typeRef)")
            return
        }
        #expect(parameters.count == 1)
        #expect((receiver != nil) == type.hasPrefix("String"))
        #expect(property.initializer == nil)
        guard case let .expr(expression, _) = property.getter?.body,
              case .lambdaLiteral = ast.arena.expr(expression) else {
            Issue.record("The getter must return a lambda expression")
            return
        }
    }

    @Test
    func mixedTypeUseAnnotationPlacementKeepsEachComputedGetterAttached() throws {
        let (ast, ctx) = try buildASTModule(from: """
        @Target(AnnotationTarget.TYPE)
        annotation class TypeAnn(val name: String)
        class C {
            val getterAnnotated: Int
                get(): @TypeAnn("1") Int = 123
            val propertyAnnotated: @TypeAnn("1") Int
                get(): Int = 123
        }
        """, includeStdlib: false)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let getterAnnotated = try #require(memberProperty(named: "getterAnnotated", ofClass: "C", in: ast, interner: ctx.interner))
        let propertyAnnotated = try #require(memberProperty(named: "propertyAnnotated", ofClass: "C", in: ast, interner: ctx.interner))
        guard case .expr = getterAnnotated.getter?.body else {
            Issue.record("The getter-return-annotated property's getter body must remain attached")
            return
        }
        guard case .expr = propertyAnnotated.getter?.body else {
            Issue.record("The property-type-annotated property's getter body must remain attached")
            return
        }

        guard let getterPropertyType = getterAnnotated.type,
              case .named = ast.arena.typeRef(getterPropertyType)
        else {
            Issue.record("A getter return type annotation must not move onto the property type")
            return
        }
        guard let propertyType = propertyAnnotated.type,
              case .annotated = ast.arena.typeRef(propertyType)
        else {
            Issue.record("The annotation written on the property type must remain on that type")
            return
        }
    }

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
    func topLevelTypedBlockGetterRetainsItsInitializerAndBody() throws {
        let (ast, ctx) = try buildASTModule(from: """
        var value: String = "OK"
            get(): String { return "OK" }
        """, includeStdlib: false)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let property = try #require(topLevelProperty(named: "value", in: ast, interner: ctx.interner))
        #expect(property.initializer != nil)
        #expect(property.setter == nil)
        guard case let .block(statements, _) = property.getter?.body else {
            Issue.record("The typed top-level getter must remain attached to its property")
            return
        }
        #expect(statements.count == 1)
    }

    @Test
    func blockGetterReturnTypeIsRetainedAsPropertyType() throws {
        let (ast, ctx) = try buildASTModule(from: """
        val value get(): String { return "OK" }
        """, includeStdlib: false)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let property = try #require(topLevelProperty(named: "value", in: ast, interner: ctx.interner))
        let getterReturnType = try #require(property.getter?.returnType)
        #expect(property.type == getterReturnType)
        #expect(property.initializer == nil)
    }

    @Test(arguments: [
        "object { val inner: Int get() = 42 }",
        "run { 42 }",
    ])
    func topLevelTypedBlockGetterKeepsInitializerBlockOwnership(_ initializer: String) throws {
        let (ast, ctx) = try buildASTModule(from: """
        val completion: Any = \(initializer)
            get(): Any { return "OK" }
        """, includeStdlib: false)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let property = try #require(topLevelProperty(named: "completion", in: ast, interner: ctx.interner))
        #expect(property.initializer != nil)
        guard case let .block(statements, _) = property.getter?.body else {
            Issue.record("The typed getter block must stay separate from its initializer block")
            return
        }
        #expect(statements.count == 1)
    }

    @Test
    func explicitEmptySetterRetainsAnEmptyBlockBody() throws {
        let (ast, ctx) = try buildASTModule(from: """
        class C {
            var value: Int
                get() = 42
                set(value) {}
        }
        """, includeStdlib: false)
        let property = try #require(memberProperty(named: "value", ofClass: "C", in: ast, interner: ctx.interner))
        guard case let .block(statements, _) = property.setter?.body else {
            Issue.record("An explicit empty setter body must remain a block rather than `.unit`")
            return
        }
        #expect(statements.isEmpty)
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
        #expect(path == [KnownCompilerNames(interner: ctx.interner).int])
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
        #expect(property.setter?.parameterName == ctx.interner.intern("v"))
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
    func extensionGetterKeepsUnqualifiedGetCall() throws {
        let (ast, ctx) = try buildASTModule(from: """
        val Array<String>.minimalFirstElement: String get() = get(0)
        """)

        let initializationErrors = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0424"
        }
        #expect(initializationErrors.isEmpty, "The expression body must not be mistaken for an accessor: \(initializationErrors)")

        let property = try #require(topLevelProperty(named: "minimalFirstElement", in: ast, interner: ctx.interner))
        guard case let .expr(exprID, _) = property.getter?.body,
              case let .call(calleeID, _, arguments, _) = ast.arena.expr(exprID),
              case let .nameRef(callee, _) = ast.arena.expr(calleeID)
        else {
            Issue.record("The extension getter body must retain the unqualified get(0) call")
            return
        }
        #expect(callee == KnownCompilerNames(interner: ctx.interner).get)
        #expect(arguments.count == 1)
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

        let knownNames = KnownCompilerNames(interner: ctx.interner)
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
            #expect(callee == knownNames.get)
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
        #expect(nestedCallee == knownNames.toString)
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
        #expect(property.setter?.parameterName == ctx.interner.intern("v"))
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
        #expect(callee == KnownCompilerNames(interner: ctx.interner).sbSet)
    }

    @Test
    func bareDefaultSetterDoesNotConsumeLateinitPropertyType() throws {
        let (ast, ctx) = try buildASTModule(from: """
        class Holder {
            lateinit var instance: Holder set
        }
        """, includeStdlib: false)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let property = try #require(memberProperty(named: "instance", ofClass: "Holder", in: ast, interner: ctx.interner))
        let typeRef = try #require(property.type.flatMap { ast.arena.typeRef($0) })
        guard case let .named(path, _, nullable) = typeRef else {
            Issue.record("The property's explicit Holder type must remain intact")
            return
        }
        #expect(path.map(ctx.interner.resolve) == ["Holder"])
        #expect(!nullable)
        #expect(property.modifiers.contains(.lateinit))
        #expect(property.setter?.kind == .setter)
        #expect(property.setter?.visibility == nil)
        #expect(property.setter?.parameterName == nil)
        #expect(property.setter?.body == .unit)
    }

    @Test
    func bareDefaultSetterKeepsPrimitiveLateinitType() throws {
        let (ast, ctx) = try buildASTModule(from: """
        class Holder {
            lateinit var number: Int set
        }
        """, includeStdlib: false)

        let property = try #require(memberProperty(named: "number", ofClass: "Holder", in: ast, interner: ctx.interner))
        let typeRef = try #require(property.type.flatMap { ast.arena.typeRef($0) })
        guard case let .named(path, _, nullable) = typeRef else {
            Issue.record("The property's explicit Int type must remain intact")
            return
        }
        #expect(path.map(ctx.interner.resolve) == ["Int"])
        #expect(!nullable)
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
        #expect(member == ctx.interner.intern("let"))
        #expect(runName == KnownCompilerNames(interner: ctx.interner).run)
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
