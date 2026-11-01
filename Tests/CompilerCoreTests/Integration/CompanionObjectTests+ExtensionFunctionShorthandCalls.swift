#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

// MARK: - KSP-CAP-003: Companion-receiver extension function shorthand calls

/// `CompanionObjectTests+PrivateAccess.swift` only exercises the fully
/// qualified call form (`MyClass.Companion.extensionFun()`), which resolves
/// through plain member access on `Companion` and never reaches the
/// class-name-receiver companion fallback in
/// `CallTypeChecker+MemberCallInferenceRegularResolution.swift`. These tests
/// pin the shorthand form (`MyClass.extensionFun()`, no `.Companion.`) that
/// KSP-CAP-003 is specifically about.
extension CompanionObjectTests {

    @Test func testExtensionFunctionShorthandCallsSema() throws {
        let sources: [String] = [
            // testCompanionExtensionFunctionShorthandCall
            """
            package sample0
                    class MyClass {
                        companion object
                    }

                    fun MyClass.Companion.extensionFun(): String = "extended"

                    fun main() {
                        val result: String = MyClass.extensionFun()
                    }

            """,

            // testCompanionExtensionFunctionWithArgumentShorthandCall
            """
            package sample1
                    class Widget {
                        companion object
                    }

                    fun Widget.Companion.create(count: Int): Widget = Widget()

                    fun main() {
                        val w: Widget = Widget.create(3)
                    }

            """,

            // testCompanionExtensionPropertyShorthandCall
            """
            package sample2
                    class Data {
                        companion object
                    }

                    val Data.Companion.extensionProp: Int get() = 42

                    fun main() {
                        val value: Int = Data.extensionProp
                    }

            """,

            // testNamedCompanionExtensionFunctionShorthandCall
            """
            package sample3
                    class Service {
                        companion object Factory
                    }

                    fun Service.Factory.create(): Service = Service()

                    fun main() {
                        val s: Service = Service.create()
                    }

            """,

            // testInterfaceCompanionExtensionFunctionShorthandCall
            """
            package sample4
                    interface ClockLike {
                        companion object
                    }

                    fun ClockLike.Companion.system(): Int = 42

                    fun main() {
                        val result: Int = ClockLike.system()
                    }

            """,

            // testExtensionFunctionOnBundledInstantCompanionShorthandCall
            """
            package sample5
                    import kotlin.time.Instant

                    fun Instant.Companion.epoch(): Instant = Instant.fromEpochMilliseconds(0L)

                    fun main() {
                        val i: Instant = Instant.epoch()
                    }

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // testCompanionExtensionFunctionShorthandCall

            do {
                let sample0Path = paths[0]
                let sampleDiags = diagnosticsForPath(sample0Path, in: ctx)


                        #expect(
                            !sampleDiags.hasError,
                            "Expected no sema errors for companion extension function shorthand call, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testCompanionExtensionFunctionWithArgumentShorthandCall

            do {
                let sample1Path = paths[1]
                let sampleDiags = diagnosticsForPath(sample1Path, in: ctx)


                        #expect(
                            !sampleDiags.hasError,
                            "Expected no sema errors for companion extension function (with argument) shorthand call, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testCompanionExtensionPropertyShorthandCall

            do {
                let sample2Path = paths[2]
                let sampleDiags = diagnosticsForPath(sample2Path, in: ctx)


                        #expect(
                            !sampleDiags.hasError,
                            "Expected no sema errors for companion extension property shorthand call, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testNamedCompanionExtensionFunctionShorthandCall

            do {
                let sample3Path = paths[3]
                let sampleDiags = diagnosticsForPath(sample3Path, in: ctx)


                        #expect(
                            !sampleDiags.hasError,
                            "Expected no sema errors for named companion extension function shorthand call, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testInterfaceCompanionExtensionFunctionShorthandCall

            do {
                let sample4Path = paths[4]
                let sampleDiags = diagnosticsForPath(sample4Path, in: ctx)


                        #expect(
                            !sampleDiags.hasError,
                            "Expected no sema errors for interface companion extension function shorthand call, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testExtensionFunctionOnBundledInstantCompanionShorthandCall

            do {
                let sample5Path = paths[5]
                let sampleDiags = diagnosticsForPath(sample5Path, in: ctx)


                        #expect(
                            !sampleDiags.hasError,
                            "Expected no sema errors for extension function on bundled Instant.Companion, got: \(sampleDiags.map(\.code))"
                        )

            }

        }
    }



    /// Mirrors the exact KSP-472 blocker scenario: a Kotlin-source extension
    /// function declared on the bundled `kotlin.time.Instant` class's
    /// synthetic `Companion` (registered in
    /// `HeaderHelpers+SyntheticInstantStubs.swift`), invoked with the
    /// shorthand call form. This is the concrete proof that KSP-CAP-003's
    /// fix unblocks KSP-472's `kk_instant_now`/`kk_clock_system_now` wiring.



    @Test func testCompanionExtensionFunctionShorthandCallKIRLowering() throws {
        let source = """
        class MyClass {
            companion object
        }

        fun MyClass.Companion.extensionFun(): String = "extended"

        fun main() {
            val result: String = MyClass.extensionFun()
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected no KIR errors for companion extension function shorthand call, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )

        let module = try #require(ctx.kir)
        let functionNames = findAllKIRFunctions(in: module).map { function in
            ctx.interner.resolve(function.name)
        }
        #expect(
            functionNames.contains("extensionFun"),
            "Expected companion extension function in KIR, got: \(functionNames)"
        )
    }

    /// KUU-3845: `companion val Host.x`/`companion var Host.x` is stored
    /// state in the companion scope even though it parses as a top-level
    /// extension property. Lowering must emit the backing global and real
    /// implicit accessor bodies for the accessor symbols Sema registers —
    /// previously only explicit accessors were emitted, leaving `Host.x`
    /// reads as calls to an undefined property-named symbol at link time.
    @Test func testCompanionExtensionPropertyEmitsStorageAndImplicitAccessors() throws {
        let source = """
        class Host
        companion val Host.compExtVal: String = "extVal"
        companion var Host.compExtVar: Int = 1
        fun main() { println(Host.compExtVal + Host.compExtVar) }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected no KIR errors for companion extension properties, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let functions = findAllKIRFunctions(in: module)
        for name in ["compExtVal", "compExtVar"] {
            let propertySymbol = try #require(
                sema.symbols.lookup(fqName: [ctx.interner.intern(name)])
            )
            let getterSymbol = try #require(
                sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
            )
            let hasGlobal = module.arena.declarations.contains { decl in
                guard case let .global(global) = decl else { return false }
                return global.symbol == propertySymbol
            }
            #expect(
                hasGlobal,
                "Expected a KIRGlobal for \(name)'s companion extension property storage"
            )
            let getter = functions.first { $0.symbol == getterSymbol }
            #expect(
                getter != nil,
                "Expected an implicit getter function for \(name)'s accessor symbol"
            )
            #expect(
                getter?.params.count == 1,
                "\(name)'s getter should take only the companion receiver, got: \(getter?.params.count ?? -1)"
            )
        }
        let varPropertySymbol = try #require(
            sema.symbols.lookup(fqName: [ctx.interner.intern("compExtVar")])
        )
        let setterSymbol = try #require(
            sema.symbols.extensionPropertySetterAccessor(for: varPropertySymbol)
        )
        let setter = functions.first { $0.symbol == setterSymbol }
        #expect(
            setter != nil,
            "Expected an implicit setter function for compExtVar's accessor symbol"
        )
        #expect(
            setter?.params.count == 2,
            "compExtVar's setter should take the companion receiver and the value, got: \(setter?.params.count ?? -1)"
        )
    }

    /// KUU-3857: `Host.compExtVar = v` resolves through the same
    /// companion-scope receiver the read path uses and lowers to the
    /// registered setter accessor — previously the write reported
    /// KSWIFTK-SEMA-0022 because assignment lookup never considered
    /// `companion`-marked extension properties behind a class-name
    /// qualifier.
    @Test func testCompanionExtensionVarWriteResolvesAndCallsSetter() throws {
        let source = """
        class Host
        companion var Host.compExtVar: Int = 1
        fun main() {
            Host.compExtVar = 2
            println(Host.compExtVar)
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected no KIR errors for companion extension var write, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let property = try #require(
            sema.symbols.lookup(fqName: [ctx.interner.intern("compExtVar")])
        )
        let write = try #require(ast.arena.exprs.indices.first { index in
            guard case .memberAssign = ast.arena.expr(ExprID(rawValue: Int32(index))) else {
                return false
            }
            return true
        }.map { ExprID(rawValue: Int32($0)) })
        #expect(
            sema.bindings.identifierSymbol(for: write) == property,
            "Expected Host.compExtVar = 2 to bind the extension property"
        )
    }

    /// KUU-3857: `companion { }` block members live on the hidden
    /// `$CompanionBlocks` object whose flat global slots are initialized by
    /// the object's lazy-init function. A write that is the object's first
    /// access must emit the lazy-init guard *before* storing — otherwise a
    /// later read runs the object's initializers and clobbers the stored
    /// value.
    @Test func testCompanionBlockMemberWriteEmitsLazyInitBeforeStore() throws {
        let source = """
        class Blocks {
            companion {
                var blockVar = 5
            }
        }
        fun main() {
            Blocks.blockVar = 7
            println(Blocks.blockVar)
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected no KIR errors for companion-block member write, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let host = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Blocks")]))
        let blockObject = try #require(sema.symbols.companionBlockObjectSymbol(
            for: host, interner: ctx.interner
        ))
        let blockVar = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("Blocks"),
            ctx.interner.intern("$CompanionBlocks"),
            ctx.interner.intern("blockVar"),
        ]))
        #expect(sema.symbols.parentSymbol(for: blockVar) == blockObject)
        let main = try #require(findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name) == "main"
        })
        var lazyInitIndex: Int?
        var firstStorageAccessIndex: Int?
        for (index, instruction) in main.body.enumerated() {
            switch instruction {
            case let .call(_, callee, _, _, _, _, _, _):
                let name = ctx.interner.resolve(callee)
                if name.hasPrefix("__object_lazy_init") || name.hasPrefix("__companion_lazy_init") {
                    lazyInitIndex = lazyInitIndex ?? index
                }
            case let .loadGlobal(_, symbol), let .storeGlobal(_, symbol):
                if symbol == blockVar {
                    firstStorageAccessIndex = firstStorageAccessIndex ?? index
                }
            case let .copy(_, to):
                if case let .symbolRef(symbol)? = module.arena.expr(to), symbol == blockVar {
                    firstStorageAccessIndex = firstStorageAccessIndex ?? index
                }
            default:
                continue
            }
        }
        let storageIndex = try #require(
            firstStorageAccessIndex,
            "Expected main to access the $CompanionBlocks member's global slot"
        )
        let guardIndex = try #require(
            lazyInitIndex,
            "Expected main to call the $CompanionBlocks lazy-init guard"
        )
        #expect(
            guardIndex < storageIndex,
            "The object lazy-init guard must run before the member write (guard at \(guardIndex), access at \(storageIndex))"
        )
    }

}
#endif
