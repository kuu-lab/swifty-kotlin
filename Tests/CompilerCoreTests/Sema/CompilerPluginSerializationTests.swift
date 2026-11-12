#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

/// Built-in compiler plugins (`org.jetbrains.kotlinx.serialization`):
/// The Serialization plugin synthesizes a companion object (if missing),
/// a `serializer()` function on the companion object, and a nested
/// `$serializer` class on `@Serializable` classes.
@Suite
struct CompilerPluginSerializationTests {

    private let serializationStubSource = """
    package kotlinx.serialization

    interface KSerializer<T>

    annotation class Serializable
    """

    private let enumSerializerStubSource = """
    package kotlinx.serialization.internal

    import kotlinx.serialization.KSerializer

    fun <T : Enum<T>> createSimpleEnumSerializer(serialName: String, values: Array<T>): KSerializer<T> = TODO()
    """

    private let validSerializableEnumSource = """
    package com.example

    import kotlinx.serialization.Serializable

    @Serializable
    enum class Color { RED, GREEN }
    """

    private let validSerializableSource = """
    package com.example

    import kotlinx.serialization.Serializable

    @Serializable
    class User(val name: String, val age: Int)
    """

    private func findMethodSymbols(
        named name: String,
        inSymbol parentSymbol: SymbolID,
        in ctx: CompilationContext
    ) throws -> [SymbolID] {
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let targetName = interner.intern(name)
        guard let parentSym = sema.symbols.symbol(parentSymbol) else { return [] }
        return sema.symbols.lookupAll(fqName: parentSym.fqName + [targetName]).filter {
            sema.symbols.parentSymbol(for: $0) == parentSymbol
                && sema.symbols.symbol($0)?.kind == .function
        }
    }

    @Test
    func testGeneratesSerializerAndCompanion() throws {
        try withTemporaryFiles(contents: [serializationStubSource, validSerializableSource]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump
            )
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[1], in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "serialization plugin must not produce errors for valid @Serializable: \(errors.map { "\($0.code): \($0.message)" }.joined(separator: " | "))")

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let classFQName = [interner.intern("com"), interner.intern("example"), interner.intern("User")]
            let classSymbol = try #require(sema.symbols.lookup(fqName: classFQName))

            // 1. Companion object synthesized
            let companionID = try #require(sema.symbols.companionObjectSymbol(for: classSymbol))
            let companionSym = try #require(sema.symbols.symbol(companionID))
            #expect(companionSym.kind == .object)

            // 2. serializer() on companion object
            let serializerMethods = try findMethodSymbols(named: "serializer", inSymbol: companionID, in: ctx)
            #expect(serializerMethods.count == 1, "expected exactly one serializer() method on companion")
            let serializerSig = try #require(sema.symbols.functionSignature(for: serializerMethods[0]))
            #expect(serializerSig.parameterTypes.isEmpty)

            // 3. Nested $serializer class
            let genSerializerFQName = classFQName + [interner.intern("$serializer")]
            let genSerializerSym = try #require(sema.symbols.lookup(fqName: genSerializerFQName))
            #expect(sema.symbols.symbol(genSerializerSym)?.kind == .class)
        }
    }

    @Test
    func testGeneratedSerializerReachesKIR() throws {
        try withTemporaryFiles(contents: [serializationStubSource, validSerializableSource]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump
            )
            try runToKIR(ctx)
            let errors = diagnosticsForPath(paths[1], in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "KIR lowering must succeed: \(errors.map { "\($0.code): \($0.message)" }.joined(separator: " | "))")

            let kir = try #require(ctx.kir)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let classFQName = [interner.intern("com"), interner.intern("example"), interner.intern("User")]
            let classSymbol = try #require(sema.symbols.lookup(fqName: classFQName))
            let companionID = try #require(sema.symbols.companionObjectSymbol(for: classSymbol))

            let serializerMethods = try findMethodSymbols(named: "serializer", inSymbol: companionID, in: ctx)
            #expect(serializerMethods.count == 1)
            let serializerFunc = try #require(kir.arena.function(for: serializerMethods[0]))
            #expect(serializerFunc.params.count == 1) // receiver
        }
    }

    @Test
    func testGenericClassSerializerParameters() throws {
        let genericSource = """
        package com.example

        import kotlinx.serialization.Serializable

        @Serializable
        class Box<T>(val item: T)
        """
        try withTemporaryFiles(contents: [serializationStubSource, genericSource]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump
            )
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[1], in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "generic @Serializable must succeed: \(errors.map { "\($0.code): \($0.message)" }.joined(separator: " | "))")

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let classFQName = [interner.intern("com"), interner.intern("example"), interner.intern("Box")]
            let classSymbol = try #require(sema.symbols.lookup(fqName: classFQName))
            let companionID = try #require(sema.symbols.companionObjectSymbol(for: classSymbol))

            let serializerMethods = try findMethodSymbols(named: "serializer", inSymbol: companionID, in: ctx)
            #expect(serializerMethods.count == 1)
            let serializerSig = try #require(sema.symbols.functionSignature(for: serializerMethods[0]))
            // 1 type parameter T -> serializer(typeSerial0: KSerializer<T>) takes 1 parameter
            #expect(serializerSig.parameterTypes.count == 1)
        }
    }

    @Test
    func testWithoutAnnotationNoSyntheticSerializer() throws {
        let plainSource = """
        package com.example

        class PlainUser(val name: String)
        """
        try withTemporaryFiles(contents: [serializationStubSource, plainSource]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump
            )
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let classFQName = [interner.intern("com"), interner.intern("example"), interner.intern("PlainUser")]
            let classSymbol = try #require(sema.symbols.lookup(fqName: classFQName))
            #expect(sema.symbols.companionObjectSymbol(for: classSymbol) == nil)
        }
    }

    @Test
    func testUnsupportedKindErrors() throws {
        let invalidKindSource = """
        package com.example

        import kotlinx.serialization.Serializable

        @Serializable
        interface Foo

        @Serializable
        annotation class Bar
        """
        try withTemporaryFiles(contents: [serializationStubSource, invalidKindSource]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump
            )
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[1], in: ctx).filter { $0.severity == .error }
            let kindErrors = errors.filter { $0.code == "KSWIFTK-SEMA-0487" }
            #expect(kindErrors.count >= 2, "expected KSWIFTK-SEMA-0487 for interface/annotation, got: \(errors.map { "\($0.code): \($0.message)" }.joined(separator: " | "))")
        }
    }

    @Test
    func testInnerClassErrors() throws {
        let innerSource = """
        package com.example

        import kotlinx.serialization.Serializable

        class Outer {
            @Serializable
            inner class InnerUser(val x: Int)
        }
        """
        try withTemporaryFiles(contents: [serializationStubSource, innerSource]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump
            )
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[1], in: ctx).filter { $0.severity == .error }
            #expect(
                errors.contains { $0.code == "KSWIFTK-SEMA-0488" },
                "expected KSWIFTK-SEMA-0488 for inner class, got: \(errors.map { "\($0.code): \($0.message)" }.joined(separator: " | "))"
            )
        }
    }

    @Test
    func testExistingCompanionObjectReused() throws {
        let existingCompanionSource = """
        package com.example

        import kotlinx.serialization.Serializable

        @Serializable
        class User(val name: String) {
            companion object {
                val EXISTING = 1
            }
        }
        """
        try withTemporaryFiles(contents: [serializationStubSource, existingCompanionSource]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump
            )
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[1], in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let classFQName = [interner.intern("com"), interner.intern("example"), interner.intern("User")]
            let classSymbol = try #require(sema.symbols.lookup(fqName: classFQName))
            let companionID = try #require(sema.symbols.companionObjectSymbol(for: classSymbol))

            // User-declared companion object should NOT be marked synthetic
            #expect(!sema.symbols.symbol(companionID)!.flags.contains(.synthetic))

            // But it should have the synthesized serializer()
            let serializerMethods = try findMethodSymbols(named: "serializer", inSymbol: companionID, in: ctx)
            #expect(serializerMethods.count == 1)
        }
    }

    @Test
    func testSerializableEnumSynthesizesSerializerWithoutGeneratedClass() throws {
        let ctx = try semaContext(from: [
            enumSerializerStubSource,
            validSerializableEnumSource,
        ])
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let enumFQName = [interner.intern("com"), interner.intern("example"), interner.intern("Color")]
        let enumSymbol = try #require(sema.symbols.lookup(fqName: enumFQName))

        let serializerMethods = try findMethodSymbols(named: "serializer", inSymbol: enumSymbol, in: ctx)
        #expect(serializerMethods.count == 1, "expected a static serializer() on the enum class")
        #expect(sema.symbols.symbol(serializerMethods[0])?.flags.contains(.static) == true)
        #expect(
            sema.symbols.lookup(fqName: enumFQName + [interner.intern("$serializer")]) == nil,
            "enum serialization should use the runtime enum serializer factory, not a generated $serializer class"
        )
    }

    @Test
    func testSerializableEnumSerializerReachesKIR() throws {
        let ctx = try kirContext(from: [
            enumSerializerStubSource,
            validSerializableEnumSource,
        ])
        let kir = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let enumFQName = [interner.intern("com"), interner.intern("example"), interner.intern("Color")]
        let enumSymbol = try #require(sema.symbols.lookup(fqName: enumFQName))

        let serializerMethods = try findMethodSymbols(named: "serializer", inSymbol: enumSymbol, in: ctx)
        #expect(serializerMethods.count == 1)
        let serializerFunc = try #require(kir.arena.function(for: serializerMethods[0]))
        #expect(serializerFunc.params.isEmpty)
        let callsEnumFactory = serializerFunc.body.contains { instruction in
            guard case let .call(
                symbol: _,
                callee: callee,
                arguments: _,
                result: _,
                canThrow: _,
                thrownResult: _,
                isSuperCall: _,
                qualifiedSuperType: _
            ) = instruction else {
                return false
            }
            return interner.resolve(callee) == "createSimpleEnumSerializer"
        }
        #expect(callsEnumFactory, "enum serializer() should call kotlinx.serialization.internal.createSimpleEnumSerializer")
    }

    @Test
    func testAdditionalAnnotationConfig() throws {
        let customSource = """
        package com.example

        annotation class MySerializable

        @MySerializable
        class CustomUser(val id: Int)
        """
        let customFlag = "plugin:org.jetbrains.kotlinx.serialization:additionalAnnotation=com.example.MySerializable"
        try withTemporaryFiles(contents: [serializationStubSource, customSource]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: [customFlag]
            )
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[1], in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let classFQName = [interner.intern("com"), interner.intern("example"), interner.intern("CustomUser")]
            let classSymbol = try #require(sema.symbols.lookup(fqName: classFQName))
            let companionID = try #require(sema.symbols.companionObjectSymbol(for: classSymbol))

            let serializerMethods = try findMethodSymbols(named: "serializer", inSymbol: companionID, in: ctx)
            #expect(serializerMethods.count == 1)
        }
    }
}
#endif
