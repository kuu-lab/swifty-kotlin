#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

/// Built-in compiler plugins (`-P plugin:<id>:<key>=<value>`): the no-arg
/// plugin synthesizes a public zero-argument constructor on annotated
/// classes, matching kotlinc's `kotlin-noarg`.
@Suite
struct CompilerPluginNoArgTests {

    private let pluginFlag = "plugin:org.jetbrains.kotlin.noarg:annotation=com.example.Entity"

    private let source = """
    package com.example

    annotation class Entity

    @Entity
    class Foo(val id: Int) {
        var counter = 0
        init { counter = 42 }
    }
    """

    private func zeroArgConstructorSymbols(in ctx: CompilationContext, className: String = "Foo") throws -> [SymbolID] {
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let classFQName = [
            interner.intern("com"), interner.intern("example"), interner.intern(className),
        ]
        guard let classSymbol = sema.symbols.lookup(fqName: classFQName) else {
            return []
        }
        return sema.symbols.lookupAll(fqName: classFQName + [interner.intern("<init>")]).filter {
            sema.symbols.parentSymbol(for: $0) == classSymbol
                && sema.symbols.symbol($0)?.kind == .constructor
                && sema.symbols.functionSignature(for: $0)?.parameterTypes.isEmpty == true
        }
    }

    @Test(arguments: [false, true])
    func testGeneratesZeroArgConstructor(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: useArtifact ? .executable : .kirDump,
                frontendFlags: [pluginFlag],
                allowDefaultStdlibLibrary: useArtifact
            )
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "noarg plugin must not break compilation: \(errors.map { "\($0.code): \($0.message)" }.joined(separator: " | "))")

            let ctors = try zeroArgConstructorSymbols(in: ctx)
            #expect(ctors.count == 1, "expected exactly one plugin-generated zero-arg constructor")
            let sema = try #require(ctx.sema)
            #expect(sema.pluginGeneratedConstructors[ctors[0]] != nil)
            // kotlinc marks the generated constructor @Deprecated(HIDDEN) so
            // Kotlin call resolution cannot select it.
            #expect(sema.symbols.annotations(for: ctors[0]).contains {
                $0.annotationFQName == "kotlin.Deprecated" && $0.arguments.contains("level=HIDDEN")
            })
        }
    }

    @Test(arguments: [false, true])
    func testWithoutPluginFlagNoZeroArgConstructor(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: useArtifact ? .executable : .kirDump,
                allowDefaultStdlibLibrary: useArtifact
            )
            try runSema(ctx)
            #expect(try zeroArgConstructorSymbols(in: ctx).isEmpty)
        }
    }

    @Test
    func testSkipsPrimaryWithAllDefaultParameters() throws {
        let source = """
        package com.example

        annotation class Entity

        @Entity
        class Foo(val id: Int = 0)
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: [pluginFlag]
            )
            try runSema(ctx)
            // The built-in all-defaults no-arg constructor already covers
            // this class; the plugin must not add a second <init>()V.
            let sema = try #require(ctx.sema)
            #expect(sema.pluginGeneratedConstructors.isEmpty)
        }
    }

    @Test
    func testSkipsWhenExplicitZeroArgConstructorExists() throws {
        let source = """
        package com.example

        annotation class Entity

        @Entity
        class Foo(val id: Int) {
            constructor() : this(0)
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: [pluginFlag]
            )
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            #expect(sema.pluginGeneratedConstructors.isEmpty)
        }
    }

    @Test
    func testSuperWithoutZeroArgConstructorErrors() throws {
        let source = """
        package com.example

        annotation class Entity

        open class Base(val b: Int)

        @Entity
        class Child(val x: Int) : Base(0)
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: [pluginFlag]
            )
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(
                errors.contains { $0.message.contains("zero-argument constructor was not found in the superclass") },
                "expected the no-arg plugin's superclass diagnostic, got: \(errors.map { "\($0.code): \($0.message)" }.joined(separator: " | "))"
            )
        }
    }

    @Test
    func testGeneratedConstructorReachesKIR() throws {
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: [pluginFlag]
            )
            try runToKIR(ctx)
            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "KIR lowering must accept the plugin constructor: \(errors.map { "\($0.code): \($0.message)" }.joined(separator: " | "))")
            let kir = try #require(ctx.kir)
            let ctors = try zeroArgConstructorSymbols(in: ctx)
            #expect(ctors.count == 1)
            let function = try #require(kir.arena.function(for: ctors[0]))
            // KIR constructor functions carry the implicit receiver as their
            // only parameter when the signature has no value parameters.
            #expect(function.params.count == 1)
            let sema = try #require(ctx.sema)
            #expect(sema.pluginGeneratedConstructors[ctors[0]]?.runsInitializers == false)
            let containsInitConstant = function.body.contains { instruction in
                if case let .constValue(_, value) = instruction, value == .intLiteral(42) {
                    return true
                }
                return false
            }
            #expect(!containsInitConstant, "default no-arg constructor must skip property initializers and init blocks")
        }
    }

    @Test
    func testInvokeInitializersFlagRunsInitializersInKIR() throws {
        let invokeFlag = "plugin:org.jetbrains.kotlin.noarg:invokeInitializers=true"
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: [pluginFlag, invokeFlag]
            )
            try runToKIR(ctx)
            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "KIR lowering must accept the plugin constructor with invokeInitializers: \(errors.map { "\($0.code): \($0.message)" }.joined(separator: " | "))")
            let kir = try #require(ctx.kir)
            let ctors = try zeroArgConstructorSymbols(in: ctx)
            #expect(ctors.count == 1)
            let sema = try #require(ctx.sema)
            #expect(sema.pluginGeneratedConstructors[ctors[0]]?.runsInitializers == true)

            let function = try #require(kir.arena.function(for: ctors[0]))
            #expect(function.params.count == 1)
            let containsInitConstant = function.body.contains { instruction in
                if case let .constValue(_, value) = instruction, value == .intLiteral(42) {
                    return true
                }
                return false
            }
            #expect(containsInitConstant, "invokeInitializers=true must emit property initializers and init blocks")
        }
    }

    @Test
    func testGeneratedConstructorIsHiddenFromKotlinCalls() throws {
        let callSource = """
        package com.example

        annotation class Entity

        @Entity
        class Foo(val id: Int)

        fun test() {
            val f = Foo()
        }
        """
        try withTemporaryFiles(contents: [callSource]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: [pluginFlag]
            )
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(!errors.contains { $0.code == "KSWIFTK-SEMA-DEPRECATED" }, "Synthetic constructor must be hidden from lookup, not emitted as deprecated")
            #expect(errors.contains { $0.message.contains("parameter") || $0.code.contains("PARAMETER") || $0.code.contains("ARGUMENT") || $0.code.contains("UNRESOLVED") })
        }
    }
}
#endif
