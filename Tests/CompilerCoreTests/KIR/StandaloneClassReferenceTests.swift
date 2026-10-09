#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct StandaloneClassReferenceTests {

    @Test func testDeepQualifiedClassLiteralDoesNotEmitConstructorCalls() throws {
        let ctx = makeContextFromSource("""
        package Sample.deep
        class Outer { class Nested(val value: Int) { class Deep(val value: Int) } }
        fun main() { println(Outer.Nested.Deep::class) }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let calls = kirCalls(in: body)
        let initializerName = ctx.interner.resolve(KnownCompilerNames(interner: ctx.interner).initName)
        #expect(calls.contains { $0.callee == KIRRuntimeFunction.kClassCreate.name(in: ctx.interner) })
        #expect(!calls.contains {
            $0.symbol.flatMap(sema.symbols.symbol)?.kind == .constructor
                || ctx.interner.resolve($0.callee).contains(initializerName)
        })
    }

    @Test func testStandaloneReifiedClassRefEmitsKClassCreate() throws {
        let source = """
        inline fun <reified T> classOf(): Any = T::class
        fun main() {
            val kc = classOf<Int>()
            println(kc)
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let calls = kirCalls(in: body)
        #expect(
            calls.contains { $0.callee == KIRRuntimeFunction.kClassCreate.name(in: ctx.interner) },
            "Expected __kk_kclass_create for standalone T::class after inline expansion, got: \(calls)"
        )
    }

    @Test func testStandaloneConcreteAndPrimitiveClassRefsEmitKClassCreate() throws {
        for typeName in ["String", "Int", "Long", "Double", "Boolean"] {
            let source = """
            fun main() {
                val kc = \(typeName)::class
                println(kc)
            }
            """
            let ctx = makeContextFromSource(source)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let calls = kirCalls(in: body)
            #expect(
                calls.contains { $0.callee == KIRRuntimeFunction.kClassCreate.name(in: ctx.interner) },
                Comment(rawValue: "Expected __kk_kclass_create for standalone \(typeName)::class, got: \(calls)")
            )
        }
    }

    /// `T::class.simpleName` (chained) after inline expansion.
    ///
    /// KSP-496 moved `simpleName` to an ordinary Kotlin extension property
    /// (Sources/CompilerCore/Stdlib/kotlin/reflect/KClasses.kt), so
    /// `T::class` now always creates the KClass box (`__kk_kclass_create`)
    /// before dispatching to the `simpleName` getter — there is no longer a
    /// "direct path" that skips box creation for this member.
    @Test func testChainedClassRefSimpleNameUsesDirectPath() throws {
        let source = """
        inline fun <reified T> typeNameOf(): String = T::class.simpleName ?: "unknown"
        fun main() = println(typeNameOf<Int>())
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let calls = kirCalls(in: body)
        let getter = try kClassExtensionGetter(named: "simpleName", in: ctx)
        #expect(
            calls.contains { $0.symbol == getter },
            "Chained T::class.simpleName should resolve to the Kotlin simpleName getter, got: \(calls)"
        )
        #expect(
            calls.contains { $0.callee == KIRRuntimeFunction.kClassCreate.name(in: ctx.interner) },
            "Chained T::class.simpleName should emit __kk_kclass_create (box creation, then dispatch to the simpleName getter), got: \(calls)"
        )
    }

    @Test func testStandaloneUserClassRefEmitsKClassCreate() throws {
        let source = """
        class MyClass
        fun main() {
            val kc = MyClass::class
            println(kc)
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let calls = kirCalls(in: body)
        #expect(
            calls.contains { $0.callee == KIRRuntimeFunction.kClassCreate.name(in: ctx.interner) },
            "Expected __kk_kclass_create for standalone MyClass::class, got: \(calls)"
        )
    }

    @Test(arguments: ["", "import annotations.MyAnno", "import annotations.MyAnno as Alias", "import annotations.*"])
    func testAnnotationClassRefResolvesAndEmitsKClassCreate(importDeclaration: String) throws {
        let receiverName = importDeclaration.contains(" as ") ? "Alias" : "MyAnno"
        let packageName = importDeclaration.isEmpty ? "annotations" : "consumer"
        let ctx = makeContextFromSources([
            """
            package annotations
            annotation class MyAnno(val name: String)
            """,
            """
            package \(packageName)
            \(importDeclaration)
            import kotlin.reflect.KClass

            fun annotationClass(): KClass<\(receiverName)> = \(receiverName)::class
            fun main() {
                val kc = \(receiverName)::class
                println(kc)
            }
            """,
        ])
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let annotationSymbol = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("annotations"), ctx.interner.intern("MyAnno"),
        ]))
        let classRefID = try #require(firstExprID(in: ast) { _, expr in
            guard case let .callableRef(receiver?, member, _) = expr,
                  case let .nameRef(name, _) = ast.arena.expr(receiver) else { return false }
            return name == ctx.interner.intern(receiverName) && member == KnownCompilerNames(interner: ctx.interner).className
        })
        let targetType = try #require(sema.bindings.classRefTargetType(for: classRefID))
        #expect(targetType == sema.types.make(.classType(ClassType(classSymbol: annotationSymbol))))
        #expect(sema.bindings.exprType(for: classRefID) == sema.types.makeKClassType(argument: targetType))

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        #expect(kirCalls(in: body).contains { $0.callee == KIRRuntimeFunction.kClassCreate.name(in: ctx.interner) })
    }

    @Test func testFindAssociatedObjectLowersToRuntimeCall() throws {
        let source = """
        import kotlin.reflect.ExperimentalAssociatedObjects
        import kotlin.reflect.findAssociatedObject

        annotation class Binding
        class Host

        @OptIn(ExperimentalAssociatedObjects::class)
        fun main() {
            val associated = Host::class.findAssociatedObject<Binding>()
            println(associated)
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let calls = kirCalls(in: body)
        #expect(
            calls.contains { $0.callee == KIRRuntimeFunction.kClassFindAssociatedObject.name(in: ctx.interner) },
            "Expected findAssociatedObject to lower to __kk_kclass_find_associated_object, got: \(calls)"
        )
    }

    @Test func testThisClassRefEmitsDynamicKClassLookup() throws {
        let source = """
        class Foo {
            fun getKClass(): Any = this::class
        }
        fun main() {
            val f = Foo()
            println(f.getKClass())
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "getKClass", in: module, interner: ctx.interner)
        let calls = kirCalls(in: body)
        #expect(
            calls.contains { $0.callee == KIRRuntimeFunction.kClassOf.name(in: ctx.interner) },
            "Expected __kk_kclass_of for this::class, got: \(calls)"
        )
    }

    @Test func testBoundClassRefsEmitDynamicLookupAndEvaluateReceiverOnce() throws {
        let ctx = makeContextFromSource("""
        class Foo
        fun makeFoo(): Foo = Foo()
        fun <T : Any> classOf(value: T) = value::class
        fun main() {
            val f = Foo()
            val Foo = f
            println(f::class.simpleName)
            println(Foo::class.simpleName)
            println(1::class.simpleName)
            println("x"::class.simpleName)
            println(makeFoo()::class.simpleName)
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let calls = kirCalls(in: body)
        #expect(calls.filter { $0.callee == KIRRuntimeFunction.kClassOf.name(in: ctx.interner) }.count == 5)
        #expect(kirCalls(to: try findKIRFunction(named: "makeFoo", in: module, interner: ctx.interner).symbol, in: body).count == 1)
        let genericBody = try findKIRFunctionBody(named: "classOf", in: module, interner: ctx.interner)
        #expect(kirCalls(in: genericBody).contains { $0.callee == KIRRuntimeFunction.kClassOf.name(in: ctx.interner) })
    }

    @Test func testNullableBoundClassRefsAreRejected() throws {
        let ctx = makeContextFromSource("""
        fun nullableClass(value: Any?) = value::class
        fun nullClass() = null::class
        fun <T> unconstrainedClass(value: T) = value::class
        fun <T : Any?> nullableBoundClass(value: T) = value::class
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-CLASS-REF-NULLABLE"
        }.count == 4)
    }

    @Test func testRuntimeTypeCheckTokenEncodesAdditionalPrimitives() {
        let cases: [(PrimitiveType, Int64, String)] = [
            (.long, 11, "Long"),
            (.double, 12, "Double"),
            (.float, 13, "Float"),
            (.char, 14, "Char"),
        ]
        let (sema, _, types, interner) = makeSemaModule()
        for (kind, expectedBase, label) in cases {
            let type = types.make(.primitive(kind, .nonNull))
            let encoded = RuntimeTypeCheckToken.encode(type: type, sema: sema, interner: interner)
            #expect(encoded & 0xFF == expectedBase, Comment(rawValue: "\(label) should encode with base \(expectedBase)"))
            #expect(encoded != 0, Comment(rawValue: "\(label) token must not be unknownBase (0)"))
        }
    }

    @Test func testKIRResultTypeIsKClassNotAny() throws {
        let source = """
        fun main() {
            val kc = Int::class
            println(kc)
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let creation = try #require(kirCalls(to: .kClassCreate, in: body, interner: ctx.interner).first)
        let result = try #require(creation.result)
        let resultType = try #require(module.arena.exprType(result))
        let sema = try #require(ctx.sema)
        if case .kClassType = sema.types.kind(of: resultType) { return }
        Issue.record("Expected KClass result type, got: \(sema.types.kind(of: resultType))")
    }

    /// KSP-496: `cast`/`safeCast` are bundled Kotlin extensions
    /// (Stdlib/kotlin/reflect/KClasses.kt), so call sites must delegate to
    /// them instead of being special-cased into a direct runtime call.
    private func expectBundledReflectDelegation(
        source: String,
        functions: [String],
        extensionName: String,
        runtimeCallee: KIRRuntimeFunction
    ) throws {
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let extensionSymbol = try #require(sema.symbols.lookup(
            fqName: ["kotlin", "reflect", extensionName].map(ctx.interner.intern)
        ))
        for functionName in functions {
            let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)
            let calls = kirCalls(in: body)
            #expect(
                calls.contains { $0.symbol == extensionSymbol },
                "Expected \(functionName) to call the bundled Kotlin \(extensionName) extension"
            )
            #expect(
                !calls.contains { $0.callee == runtimeCallee.name(in: ctx.interner) },
                "Expected \(functionName) not to emit \(runtimeCallee) directly"
            )
        }
    }

    @Test func testDirectKClassCastDelegatesToBundledExtension() throws {
        try expectBundledReflectDelegation(
            source: """
            fun castString(value: Any?): String = String::class.cast(value)
            """,
            functions: ["castString"],
            extensionName: "cast",
            runtimeCallee: .kClassCast
        )
    }

    @Test func testKClassCastViaLocalAndParameterDelegateToBundledExtension() throws {
        try expectBundledReflectDelegation(
            source: """
            import kotlin.reflect.KClass

            fun castViaLocal(value: Any?): String {
                val klass = String::class
                return klass.cast(value)
            }

            fun <T : Any> castWithClass(klass: KClass<T>, value: Any?): T = klass.cast(value)
            """,
            functions: ["castViaLocal", "castWithClass"],
            extensionName: "cast",
            runtimeCallee: .kClassCast
        )
    }

    @Test func testDirectKClassSafeCastDelegatesToBundledExtension() throws {
        try expectBundledReflectDelegation(
            source: """
            fun safeCastString(value: Any?): String? = String::class.safeCast(value)
            """,
            functions: ["safeCastString"],
            extensionName: "safeCast",
            runtimeCallee: .kClassSafeCast
        )
    }

    @Test func testKClassSafeCastViaLocalAndParameterDelegateToBundledExtension() throws {
        try expectBundledReflectDelegation(
            source: """
            import kotlin.reflect.KClass

            fun safeCastViaLocal(value: Any?): String? {
                val klass = String::class
                return klass.safeCast(value)
            }

            fun <T : Any> safeCastWithClass(klass: KClass<T>, value: Any?): T? = klass.safeCast(value)
            """,
            functions: ["safeCastViaLocal", "safeCastWithClass"],
            extensionName: "safeCast",
            runtimeCallee: .kClassSafeCast
        )
    }
}
#endif
