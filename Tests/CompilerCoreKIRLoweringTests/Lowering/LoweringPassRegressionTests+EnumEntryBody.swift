#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

// Enum values use an ordinal-backed representation in KIR. Entry-body
// overrides therefore need a generated ordinal switch rather than a heap-backed
// anonymous subclass.
extension LoweringPassRegressionTests {
    @Test
    func testEnumEntryBodyOverridesResolveAndLowerThroughOrdinalDispatch() throws {
        let source = """
        enum class E(val w: Int) {
            X(1) {
                override fun f() = "x"
            },
            Y(2) {
                override fun f() = "y"
            };
            abstract fun f(): String
        }

        enum class Op {
            PLUS {
                override fun apply(a: Int, b: Int) = a + b
            },
            TIMES {
                override fun apply(a: Int, b: Int) = a * b
            };
            abstract fun apply(a: Int, b: Int): Int
        }

        fun main() {
            println(E.X.f())
            println(Op.TIMES.apply(2, 3))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "EnumEntryBody",
                emit: .kirDump
            )
            try runToLowering(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "enum entry body references should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let functions = findAllKIRFunctions(in: module)
            let dispatchFunctions = functions.filter {
                ctx.interner.resolve($0.name).hasPrefix("$enumEntryDispatch$")
            }
            #expect(dispatchFunctions.count == 2)

            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let mainCallees = extractCallees(from: mainBody, interner: ctx.interner)
            #expect(mainCallees.filter { $0.hasPrefix("$enumEntryDispatch$") }.count == 2)

            for dispatch in dispatchFunctions {
                let targetCalls = dispatch.body.compactMap { instruction -> (SymbolID, Int)? in
                    guard case let .call(symbol, callee, arguments, _, _, _, _, _) = instruction,
                          let symbol = symbol,
                          (callee == ctx.interner.intern("f") || callee == ctx.interner.intern("apply"))
                    else {
                        return nil
                    }
                    return (symbol, arguments.count)
                }
                #expect(targetCalls.count == 2)
                #expect(targetCalls.allSatisfy { $0.1 == 1 || $0.1 == 3 })
                #expect(targetCalls.allSatisfy { symbol, _ in
                    functions.contains { $0.symbol == symbol }
                })
            }
        }
    }

    @Test
    func testSecondaryConstructorOnlyEnumBodyValLowersWithoutUnresolvedCall() throws {
        // KUU-2871: constructor writes to a body `val` must target enum entry storage.
        let source = """
        enum class Test {
            A(0),
            B;

            val n: Int

            constructor(n: Int) { this.n = n }
            constructor() : this(0)
        }
        fun main() { println(Test.A.n == Test.B.n) }
        """
        let ctx = makeContextFromSource(source, moduleName: "EnumSecondaryConstructorBodyVal")
        try runToLowering(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "secondary-constructor enum body val should lower without verifier errors: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
        let module = try #require(ctx.kir)
        let ensureInit = try #require(findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name) == "$enumEnsureInit$"
        })
        #expect(!ensureInit.body.contains { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
            return ctx.interner.resolve(callee) == "n"
        })
    }

    @Test
    func testEnumEntryBodyOverrideInheritedFromInterfaceUsesOrdinalDispatch() throws {
        let source = """
        interface F {
            fun f(): String
        }

        enum class E : F {
            X {
                override fun f() = "x"
            },
            Y {
                override fun f() = "y"
            };
        }

        fun main() {
            println(E.X.f())
            println(E.Y.f())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "EnumEntryBodyInterface",
                emit: .kirDump
            )
            try runToLowering(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "interface-inherited enum entry overrides should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let functions = findAllKIRFunctions(in: module)
            let dispatchFunctions = functions.filter {
                ctx.interner.resolve($0.name).hasPrefix("$enumEntryDispatch$")
            }
            #expect(dispatchFunctions.count == 1)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            #expect(extractCallees(from: mainBody, interner: ctx.interner).contains {
                $0.hasPrefix("$enumEntryDispatch$")
            })
        }
    }

    /// KUU-3892: an interface default `fun` invoked unqualified on `this`
    /// inside an enum member body must route through the enum's
    /// `$enumEntryDispatch$` ordinal helper — like the qualified `E.X.f()`
    /// form — instead of binding straight to the interface's default
    /// implementation and ignoring the entry's own override.
    @Test
    func testImplicitThisInterfaceCallInsideEnumMemberUsesOrdinalDispatch() throws {
        let source = """
        interface Fun { fun f(): String = "F" }
        enum class E : Fun {
            X { override fun f() = "XF" },
            Y;
            fun test() = f()
        }
        fun main() {
            println(E.X.test())
            println(E.Y.test())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "EnumImplicitThisInterfaceDispatch",
                emit: .kirDump
            )
            try runToLowering(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "implicit-this interface call in enum member should lower: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let testBody = try findKIRFunctionBody(named: "test", in: module, interner: ctx.interner)
            let testCallees = extractCallees(from: testBody, interner: ctx.interner)
            #expect(
                testCallees.contains { $0.hasPrefix("$enumEntryDispatch$") },
                "unqualified f() must call the $enumEntryDispatch$ helper, got \(testCallees)"
            )
            // The call must not bind straight to the interface default `Fun.f`.
            #expect(testBody.allSatisfy { instruction in
                guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction,
                      symbol != nil
                else {
                    return true
                }
                return ctx.interner.resolve(callee) != "f"
            })
        }
    }

    @Test
    func testInnerClassInEnumEntryBodyResolvesAndLowers() throws {
        let source = """
        enum class A {
            X {
                val x = "OK"
                inner class Inner {
                    val y = x
                }
                val z = Inner()
                override val test: String
                    get() = z.y
            };
            abstract val test: String
        }
        fun boxA() = A.X.test

        enum class B {
            X {
                val x = "OK"
                inner class Inner {
                    fun foo() = this@X.x
                }
                val z = Inner()
                override val test = z.foo()
            };
            abstract val test: String
        }
        fun boxB() = B.X.test

        enum class Mode {
            A {
                inner class Child
                val child = Child()
            }
        }

        class RegularOwner {
            inner class Child
        }
        fun ordinaryInnerControl() = RegularOwner().Child()

        enum class EntryControl {
            A {
                val result = "OK"
                fun read() = result
                override val value = read()
            };
            abstract val value: String
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "EnumEntryNestedInnerClass",
                emit: .kirDump
            )
            try runToLowering(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { $0.message }.joined(separator: ", ")
            #expect(
                !ctx.diagnostics.hasError,
                "enum-entry nested inner classes should resolve and lower: \(diagnosticSummary)"
            )

            let module = try #require(ctx.kir)
            let functions = findAllKIRFunctions(in: module)
            let computedGetterHelpers = functions.filter { function in
                ctx.interner.resolve(function.name).hasPrefix("$enumConstructorProperty$")
                    && function.body.contains { instruction in
                        guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                        return callee == ctx.interner.intern("get")
                    }
            }
            #expect(computedGetterHelpers.count == 1)

            let sema = try #require(ctx.sema)
            let entryClassName = ctx.interner.intern("Child")
            let expectedFQName = ["Mode", "A", "Child"].map { ctx.interner.intern($0) }
            let child = try #require(sema.symbols.lookupByShortName(entryClassName).first { symbol in
                sema.symbols.symbol(symbol)?.fqName == expectedFQName
            })
            #expect(sema.symbols.symbol(child)?.flags.contains(.innerClass) == true)
            #expect(sema.symbols.outerInstanceFieldSymbol(for: child) != nil)
        }
    }
}
#endif
