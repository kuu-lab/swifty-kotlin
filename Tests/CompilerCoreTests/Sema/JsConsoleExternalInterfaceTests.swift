#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct JsConsoleExternalInterfaceTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Console external interface surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testConsoleInterfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "Console"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.Console must be registered"
        )
        let info = try #require(sema.symbols.symbol(symbol))

        #expect(info.kind == .interface)
        #expect(info.visibility == .public)
        #expect(info.flags.contains(.synthetic))
    }

    @Test func testConsolePropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let packageFQName = ["kotlin", "js"].map { interner.intern($0) }
        let consoleInterface = try #require(
            sema.symbols.lookup(fqName: packageFQName + [interner.intern("Console")])
        )
        let consoleType = try #require(sema.symbols.propertyType(for: consoleInterface))
        let property = try #require(
            sema.symbols.lookup(fqName: packageFQName + [interner.intern("console")]),
            "kotlin.js.console must be registered"
        )
        let info = try #require(sema.symbols.symbol(property))

        #expect(info.kind == .property)
        #expect(info.visibility == .public)
        #expect(info.flags.contains(.synthetic))
        #expect(sema.symbols.parentSymbol(for: property) == sema.symbols.lookup(fqName: packageFQName))
        #expect(sema.symbols.propertyType(for: property) == consoleType)
        #expect(sema.symbols.externalLinkName(for: property) == nil)
    }

    @Test func testConsolePropertyCanBeImportedAndUsed() {
        let source = """
        import kotlin.js.console

        fun writeLog() {
            console.log("ready")
        }
        """
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Diagnostics are asserted below.
        }

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected console property usage to type-check, got \(errors)")
    }

    @Test func testDirSignatureIsRegistered() throws {
        let (sema, interner) = try makeSema()

        try assertMember(
            named: "dir",
            parameterType: sema.types.anyType,
            isVararg: false,
            sema: sema,
            interner: interner
        )
    }

    @Test func testVarargLoggingSignaturesAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let nullableAny = sema.types.makeNullable(sema.types.anyType)

        for name in ["error", "info", "log", "warn"] {
            try assertMember(
                named: name,
                parameterType: nullableAny,
                isVararg: true,
                sema: sema,
                interner: interner
            )
        }
    }

    private func assertMember(
        named name: String,
        parameterType: TypeID,
        isVararg: Bool,
        sema: SemaModule,
        interner: StringInterner
    ) throws {
        let consoleFQName = ["kotlin", "js", "Console"].map { interner.intern($0) }
        let consoleSymbol = try #require(sema.symbols.lookup(fqName: consoleFQName))
        let consoleType = try #require(sema.symbols.propertyType(for: consoleSymbol))
        let memberFQName = consoleFQName + [interner.intern(name)]
        let member = try #require(
            sema.symbols.lookupAll(fqName: memberFQName).first { symbol in
                guard sema.symbols.symbol(symbol)?.kind == .function,
                      let signature = sema.symbols.functionSignature(for: symbol) else {
                    return false
                }
                return signature.parameterTypes == [parameterType]
            },
            "Console.\(name) member must be registered"
        )
        let info = try #require(sema.symbols.symbol(member))
        let signature = try #require(sema.symbols.functionSignature(for: member))

        #expect(info.visibility == .public)
        #expect(info.flags.contains(.synthetic))
        #expect(signature.receiverType == consoleType)
        #expect(signature.parameterTypes == [parameterType])
        #expect(signature.returnType == sema.types.unitType)
        #expect(signature.valueParameterHasDefaultValues == [false])
        #expect(signature.valueParameterIsVararg == [isVararg])
        #expect(sema.symbols.externalLinkName(for: member) == nil)
    }
}
#endif
