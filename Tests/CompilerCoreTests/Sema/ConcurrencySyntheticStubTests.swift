#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ConcurrencySyntheticStubTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test
    func testThreadClassAndFunctionSignatures() throws {
        let (sema, interner) = try makeSema()

        let threadFQName = ["java", "lang", "Thread"].map { interner.intern($0) }
        let threadSymbol = try #require(
            sema.symbols.lookup(fqName: threadFQName),
            "Expected java.lang.Thread to be registered"
        )
        #expect(sema.symbols.symbol(threadSymbol)?.kind == .class)

        let threadType = sema.types.make(.classType(ClassType(
            classSymbol: threadSymbol,
            args: [],
            nullability: .nonNull
        )))
        #expect(sema.symbols.propertyType(for: threadSymbol) == threadType)

        let threadFunctionFQName = ["kotlin", "concurrent", "thread"].map { interner.intern($0) }
        let threadFunctionSymbol = try #require(
            sema.symbols.lookup(fqName: threadFunctionFQName),
            "Expected kotlin.concurrent.thread to be registered"
        )
        let threadSignature = try #require(sema.symbols.functionSignature(for: threadFunctionSymbol))
        #expect(sema.symbols.symbol(threadFunctionSymbol)?.flags.contains(.synthetic) == true)
        #expect(sema.symbols.symbol(threadFunctionSymbol)?.flags.contains(.inlineFunction) == true)
        #expect(sema.symbols.externalLinkName(for: threadFunctionSymbol) == "kk_thread_create")
        #expect(threadSignature.receiverType == nil)
        #expect(threadSignature.returnType == threadType)
        #expect(threadSignature.parameterTypes.count == 6)
        #expect(threadSignature.parameterTypes[0] == sema.types.booleanType)
        #expect(threadSignature.parameterTypes[1] == sema.types.booleanType)
        #expect(threadSignature.parameterTypes[3] == sema.types.makeNullable(sema.types.stringType))
        #expect(threadSignature.parameterTypes[4] == sema.types.intType)

        let classLoaderFQName = ["java", "lang", "ClassLoader"].map { interner.intern($0) }
        let classLoaderSymbol = try #require(
            sema.symbols.lookup(fqName: classLoaderFQName),
            "Expected java.lang.ClassLoader to be registered"
        )
        let classLoaderType = sema.types.make(.classType(ClassType(
            classSymbol: classLoaderSymbol,
            args: [],
            nullability: .nonNull
        )))
        let nullableClassLoaderType = sema.types.makeNullable(classLoaderType)
        #expect(threadSignature.parameterTypes[2] == nullableClassLoaderType)

        let blockType = sema.types.make(.functionType(FunctionType(
            params: [],
            returnType: sema.types.unitType
        )))
        #expect(threadSignature.parameterTypes[5] == blockType)
        #expect(threadSignature.valueParameterHasDefaultValues == [true, true, true, true, true, false])
    }

    @Test
    func testThreadResolvesInSource() throws {
        let source = """
        import kotlin.concurrent.thread

        fun probe(): Unit {
            thread(
                start = false,
                isDaemon = false,
                contextClassLoader = null,
                name = "worker",
                priority = 7,
                block = {}
            )
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected thread call to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            #expect(ctx.diagnostics.diagnostics.isEmpty, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testVolatileAnnotationClassIsRegisteredWithFieldTarget() throws {
        let (sema, interner) = try makeSema()

        let volatileFQName = ["kotlin", "concurrent", "Volatile"].map { interner.intern($0) }
        let volatileSymbol = try #require(
            sema.symbols.lookup(fqName: volatileFQName),
            "Expected kotlin.concurrent.Volatile to be registered"
        )

        #expect(sema.symbols.symbol(volatileSymbol)?.kind == .annotationClass)
        #expect(sema.symbols.symbol(volatileSymbol)?.flags.contains(.synthetic) == true)
        #expect(
            sema.symbols.annotations(for: volatileSymbol).contains {
                $0.annotationFQName == "kotlin.annotation.Target"
                    && $0.arguments == ["AnnotationTarget.FIELD"]
            },
            "Expected Volatile to carry @Target(AnnotationTarget.FIELD)"
        )
    }

    @Test
    func testVolatileAnnotationResolvesInSource() throws {
        let source = """
        import kotlin.concurrent.Volatile

        class Holder {
            @Volatile
            var value: Int = 0
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected Volatile annotation to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

}
#endif
