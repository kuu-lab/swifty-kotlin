#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CallableRefTypeIdentityTests {
    @Test(arguments: ["Box<String>", "Box<List<String?>>", "Box<*>", "Box<out String>"])
    func testExplicitTypeReceiverIsUnboundAndRetainsArguments(_ receiver: String) throws {
        let ctx = makeContextFromSource("""
        class Box<T> { fun echo(value: Int): Int = value }
        fun main() { val ref = \(receiver)::echo }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let ref = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        #expect(sema.bindings.isUnboundCallableRef(ref))
        #expect(sema.bindings.captureSymbolsByExpr[ref]?.isEmpty != false)
        guard case let .functionType(function) = sema.types.kind(of: try #require(sema.bindings.exprType(for: ref))),
              case let .classType(owner) = sema.types.kind(of: try #require(function.params.first))
        else {
            Issue.record("Expected (Box<Args>, Int) -> Int.")
            return
        }
        #expect(owner.args.count == 1)
        #expect(function.params.count == 2)
        #expect(function.params[1] == sema.types.intType)
        #expect(function.returnType == sema.types.intType)
    }

    @Test func testExplicitTypeReceiverSpecializesGenericOwnerSignature() throws {
        let ctx = makeContextFromSource("""
        class Box<T> { fun echo(value: T): T = value }
        fun main() { val ref = Box<String>::echo }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let ref = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        guard case let .functionType(function) = sema.types.kind(of: try #require(sema.bindings.exprType(for: ref))) else {
            Issue.record("Expected a function type.")
            return
        }
        #expect(function.params.count == 2)
        #expect(function.params[1] == sema.types.stringType)
        #expect(function.returnType == sema.types.stringType)
        #expect(sema.bindings.isUnboundCallableRef(ref))
        #expect(sema.bindings.captureSymbolsByExpr[ref]?.isEmpty != false)
    }

    @Test(arguments: [
        "val ref: (Box<Int>, Int) -> Int = Box<String>::echo",
        "val ref = Box<Missing>::echo",
        "val ref = Missing<String>::echo",
        "val ref = Box<String>::class",
        "val ref = Box<String, Int>::echo",
        "val ref = Int<String>::plus",
    ])
    func testInvalidExplicitTypeReceiverIsRejected(_ declaration: String) throws {
        let ctx = makeContextFromSource("""
        class Box<T> { fun echo(value: Int): Int = value }
        fun main() { \(declaration) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test(arguments: [
        "val instance = Outer.Nested<String>()",
        "val instance: Outer.Nested<String> = Outer.Nested()",
        "val instance = Outer.Nested<String>(1)",
    ])
    func testNestedGenericConstructorCanSupplyUnboundReceiver(_ declaration: String) throws {
        let ctx = makeContextFromSource("""
        class Outer {
            class Nested<T>(val initial: Int = 0) { fun echo(value: Int): Int = value }
        }
        fun main() {
            \(declaration)
            val ref = Outer.Nested<String>::echo
            val result: Int = ref(instance, 42)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test func testExplicitTypeReceiverSelectsSpecializedOverload() throws {
        let ctx = makeContextFromSource("""
        class Box<T> {
            fun echo(value: T): T = value
            fun echo(value: Int): Int = value
        }
        fun main() { val ref: (Box<String>, String) -> String = Box<String>::echo }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let ref = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let target = try #require(sema.bindings.identifierSymbol(for: ref))
        let signature = try #require(sema.symbols.functionSignature(for: target))
        #expect(sema.types.typeContainsAnyTypeParam(signature.returnType))
    }

    @Test func testFunctionValueDescriptionsIncludeReferenceSignaturesAndLambdaIdentity() throws {
        let ctx = makeContextFromSource("""
        fun top(): Int = 7
        fun main() {
            val f = { 1 }
            val ref = ::top
            val anon = fun() = 2
            println(anon())
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let descriptions = body.compactMap { instruction -> String? in
            guard case let .call(_, callee, args, _, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "__kk_function_set_description",
                  case let .stringLiteral(text) = module.arena.expr(args[1])
            else { return nil }
            return ctx.interner.resolve(text)
        }
        #expect(descriptions.contains("fun top(): kotlin.Int"))
        #expect(descriptions.filter { $0 == "kotlin.Function0" }.count == 2)
    }

    @Test func testInferredFunctionReferenceNameResolvesAndLowersToMetadata() throws {
        let ctx = makeContextFromSource("""
        fun topFun() = 3
        val topVal = 4
        class Box { fun member(x: Int) = x }
        fun <T> identity(value: T): T = value
        fun main(box: Box) {
            val fr = ::topFun
            val alias = fr
            val bound = box::member
            val unbound = Box::member
            val nullable = if (true) ::topFun else null
            println(fr())
            println(fr.name)
            println(alias.name)
            println(bound.name)
            println(unbound.name)
            println(identity(fr).name)
            println(nullable?.name)
            val vr = ::topVal
            println(vr.get())
            println(vr.name)
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(callees.contains("__kk_kcallable_get_name"))
        let boxedValues = Set(body.compactMap { instruction -> KIRExprID? in
            guard case let .call(_, callee, _, result, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee).hasPrefix("kk_function_create_")
            else { return nil }
            return result
        })
        #expect(!boxedValues.isEmpty)
        #expect(body.contains { instruction in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "__kk_function_copy_description",
                  arguments.count == 2
            else { return false }
            return boxedValues.contains(arguments[1])
        })
    }

    @Test(arguments: [
        "val f = { 3 }; println(f.name)",
        "val f: () -> Int = ::topFun; println(f.name)",
        "val ref = ::topFun; val f: () -> Int = ref; println(f.name)",
    ])
    func testPlainFunctionValuesDoNotExposeReflectionName(body: String) throws {
        let ctx = makeContextFromSource("""
        fun topFun() = 3
        fun main() { \(body) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0024" && $0.message.contains("'name'")
        })
    }

    @Test func testLambdaCannotBeAssignedToKFunction() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KFunction
        fun main() {
            val f: KFunction<Int> = { 3 }
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func testBoxedFunctionReferencesResolveInheritedReflectionMembers() throws {
        let ctx = makeContextFromSource("""
        fun defaultFun(x: Int = 2) = x + 1
        class Box { fun member(x: Int) = x }
        fun <T> identity(value: T): T = value
        fun main(box: Box) {
            val ref = identity(::defaultFun)
            println(ref.parameters[0].name)
            println(ref.callBy(emptyMap()))
            println(listOf(::defaultFun)[0].call(7))
            println(identity(box::member).call(3))
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "val f = { 3 }; println(f.call())",
        "val f: () -> Int = ::topFun; println(f.call())",
    ])
    func testPlainFunctionValuesDoNotExposeReflectionCall(body: String) throws {
        let ctx = makeContextFromSource("""
        fun topFun() = 3
        fun main() { \(body) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test(arguments: [false, true])
    func testFunctionReferenceTypeSurvivesNullabilitySubstitutionAndMetadata(isSuspend: Bool) throws {
        let types = TypeSystem()
        let symbols = SymbolTable()
        let interner = StringInterner()
        let parameter = symbols.define(
            kind: .typeParameter, name: interner.intern("T"),
            fqName: [interner.intern("T")], declSite: nil, visibility: .public
        )
        let parameterType = types.make(.typeParam(TypeParamType(symbol: parameter)))
        let referenceType = types.make(.functionType(FunctionType(
            params: [parameterType], returnType: parameterType,
            isSuspend: isSuspend, isCallableReference: true
        )))
        let variables = types.makeTypeVarBySymbol([parameter])
        let variable = try #require(variables[parameter])
        let specialized = types.substituteTypeParameters(
            in: referenceType, substitution: [variable: types.intType], typeVarBySymbol: variables
        )
        let nullable = types.makeNullable(specialized)
        let token = NameMangler().encodeType(nullable, symbols: symbols, types: types, nameResolver: interner.resolve)
        let diagnostics = DiagnosticEngine()
        let decoded = try #require(DataFlowSemaPhase().decodeImportedTypeSignature(
            token: token, symbols: symbols, types: types, interner: interner,
            diagnostics: diagnostics, metadataPath: "test", ownerFQName: []
        ))
        #expect(decoded == nullable)
        guard case let .functionType(function) = types.kind(of: decoded) else {
            Issue.record("Expected function reference type")
            return
        }
        #expect(function.isCallableReference)
        #expect(function.isSuspend == isSuspend)
        #expect(function.params == [types.intType])
        #expect(function.returnType == types.intType)
        #expect(function.nullability == .nullable)
        #expect(diagnostics.diagnostics.isEmpty)
        let plain = types.make(.functionType(FunctionType(
            params: [types.intType], returnType: types.intType, isSuspend: isSuspend
        )))
        #expect(types.isSubtype(specialized, plain))
        #expect(!types.isSubtype(plain, specialized))
    }

    @Test func testSemaBindsFunctionRefKindForCallableReference() throws {
        let source = """
        fun inc(x: Int): Int = x + 1
        fun main() {
            val f = ::inc
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
        #expect(refKind == .functionRef, "::inc should be marked as a function reference.")
    }

    @Test func testSemaBindsPropertyRefKindForPropertyCallableReference() throws {
        let source = """
        val answer: Int = 42
        fun main() {
            val ref = ::answer
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
        #expect(refKind == .propertyRef, "::answer should be marked as a property reference.")
    }

    @Test func testSemaBindsFunctionRefKindForBoundCallableReference() throws {
        let source = """
        class Box {
            fun value(): Int = 42
        }
        fun main(box: Box) {
            val f = box::value
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
        #expect(refKind == .functionRef, "box::value should be marked as a function reference.")
    }

    @Test func testSemaBindsFunctionRefKindForOverloadedCallableReference() throws {
        let source = """
        fun target(x: Int): Int = x + 1
        fun target(x: String): String = x
        fun main() {
            val ref: (Int) -> Int = ::target
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
        #expect(refKind == .functionRef, "Overloaded ::target should be marked as a function reference.")
    }

    // MARK: - Generic call-site type inference tests

    /// KSP-496 (found as a side-effect while validating a property callable-ref
    /// Sema fix): a property callable reference passed directly into a generic
    /// call (e.g. `listOf<T>(vararg elements: T)`) used to be type-checked
    /// against the *unsubstituted* type parameter `T` rather than its own
    /// natural `KProperty1<Owner, Value>` type, because `inferCallableRefExpr`
    /// adopted `expectedType` verbatim even when it still mentioned a type
    /// parameter. Binding the reference's static type to a bare type variable
    /// made `lowerPropertyReferenceWrapperValue` (which requires a resolved
    /// `KProperty*` classType) bail out and fall back to a legacy bare-symbol
    /// callable path that crashes at runtime (calls the raw property accessor
    /// with no receiver — see `Scripts/diff_cases/kproperty_generic_vararg_inference.kt`
    /// for the end-to-end runtime regression).
    @Test func testUnboundPropertyRefInGenericVarargCallGetsConcreteKProperty1Type() throws {
        let source = """
        class Counter(val v: Int)
        fun main() {
            val list = listOf(Counter::v)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let kProperty1Symbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "reflect", "KProperty1"].map { interner.intern($0) })
        )

        let boundType = try #require(sema.bindings.exprType(for: callableRefExprID))
        guard case let .classType(classType) = sema.types.kind(of: boundType) else {
            Issue.record(
                "Counter::v inside listOf(...) should bind to a KProperty1 classType, got \(sema.types.renderType(boundType))"
            )
            return
        }
        #expect(
            classType.classSymbol == kProperty1Symbol,
            "Counter::v inside listOf(...) should bind to kotlin.reflect.KProperty1, not an unsubstituted type parameter."
        )
        #expect(classType.args.count == 2, "KProperty1<Counter, Int> should carry both type arguments.")
    }

    @Test func testKIREmitsKFunctionTagForFunctionCallableRef() throws {
        let source = """
        fun inc(x: Int): Int = x + 1
        fun main(): Int {
            val f = ::inc
            return f(2)
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: mainBody, interner: ctx.interner)

        #expect(
            callees.contains("kk_callable_ref_tag_kfunction"),
            "KIR main body should contain kk_callable_ref_tag_kfunction call. Callees: \(callees)"
        )
    }

    /// KSP-496 follow-up: a bare `::member` reference to a member property
    /// of the enclosing class must capture the implicit `this` receiver into
    /// the generated KProperty wrapper object, the same way an explicit
    /// `this::member` reference does — otherwise `.get()`/`.set()` on the
    /// wrapper has no instance to read/write and crashes at runtime. This
    /// checks the KIR-level signal for that capture: a `kk_array_set` store
    /// into the wrapper's capture slot, which only exists when there's a
    /// non-empty capture argument list.
    @Test func testKIRCapturesImplicitReceiverForBareMemberPropertyRef() throws {
        let source = """
        class C(val v: Int) {
            fun r(): Int {
                val ref = ::v
                return ref.get()
            }
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let rBody = try findKIRFunctionBody(named: "r", in: module, interner: ctx.interner)
        let callees = extractCallees(from: rBody, interner: ctx.interner)

        #expect(
            callees.contains("kk_array_set"),
            "Expected the bare ::v reference's wrapper to store a captured receiver (kk_array_set). Callees: \(callees)"
        )
    }

    @Test func testKIREmitsKPropertyTagForPropertyCallableRef() throws {
        let source = """
        val answer: Int = 42
        fun main(): Int {
            val ref = ::answer
            return answer
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let allCallees = findAllKIRFunctions(in: module).flatMap { function in
            return extractCallees(from: function.body, interner: ctx.interner)
        }
        #expect(
            allCallees.contains("kk_callable_ref_tag_kproperty"),
            "Property callable ref should be tagged as KProperty. Callees: \(allCallees)"
        )
        #expect(
            !(allCallees.contains("kk_callable_ref_tag_kfunction")),
            "Property callable ref should NOT be tagged as KFunction."
        )
    }

    @Test func testKIRKFunctionTagIncludesCorrectNameAndArity() throws {
        let source = """
        fun add(a: Int, b: Int): Int = a + b
        fun main(): Int {
            val f = ::add
            return f(1, 2)
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

        let tagCall = mainBody.first { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                return false
            }
            return ctx.interner.resolve(callee) == "kk_callable_ref_tag_kfunction"
        }
        guard case let .call(_, _, arguments, _, _, _, _, _) = tagCall else {
            Issue.record("Expected kk_callable_ref_tag_kfunction call in main body.")
            return
        }

        // arguments[0] = callable value, arguments[1] = name,
        // arguments[2] = return type, arguments[3] = arity,
        // arguments[4] = isSuspend flag.
        #expect(arguments.count == 5)

        if let nameExpr = module.arena.expr(arguments[1]),
           case let .stringLiteral(nameInterned) = nameExpr
        {
            #expect(ctx.interner.resolve(nameInterned) == "add")
        } else {
            Issue.record("Second argument to tag call should be string literal 'add'.")
        }

        // Verify the return type argument is the compact Int descriptor.
        if let returnTypeExpr = module.arena.expr(arguments[2]),
           case let .stringLiteral(returnTypeInterned) = returnTypeExpr
        {
            #expect(ctx.interner.resolve(returnTypeInterned) == "Int")
        } else {
            Issue.record("Third argument to tag call should be string literal 'Int'.")
        }

        if let arityExpr = module.arena.expr(arguments[3]),
           case let .intLiteral(arityValue) = arityExpr
        {
            #expect(arityValue == 2, "::add has arity 2 (a, b).")
        } else {
            Issue.record("Fourth argument to tag call should be int literal for arity.")
        }

        if let suspendExpr = module.arena.expr(arguments[4]),
           case let .intLiteral(isSuspendValue) = suspendExpr
        {
            #expect(isSuspendValue == 0, "::add is not a suspend function.")
        } else {
            Issue.record("Fifth argument to tag call should be int literal for isSuspend.")
        }
    }

    @Test func testKIRKFunctionTagForBoundCallableRef() throws {
        let source = """
        class Box {
            fun plus(x: Int): Int = x
        }
        fun main(box: Box): Int {
            val f = box::plus
            return f(7)
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: mainBody, interner: ctx.interner)

        #expect(
            callees.contains("kk_callable_ref_tag_kfunction"),
            "Bound callable ref box::plus should emit KFunction tag. Callees: \(callees)"
        )
    }

    @Test func testCallableRefTagCallsAreNonThrowing() throws {
        let source = """
        fun inc(x: Int): Int = x + 1
        fun main(): Int {
            val f = ::inc
            return f(2)
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

        let tagCall = mainBody.first { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                return false
            }
            return ctx.interner.resolve(callee) == "kk_callable_ref_tag_kfunction"
        }
        guard case let .call(_, _, _, _, canThrow, _, _, _) = tagCall else {
            Issue.record("Expected kk_callable_ref_tag_kfunction call.")
            return
        }
        #expect(!(canThrow), "Callable ref tagging call should be non-throwing.")
    }
}
#endif
