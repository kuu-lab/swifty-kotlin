#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct IterableRangeNullableContainsTests {
    @Test func nullableCallsAndOperatorsBindToSourceExtensions() throws {
        let ctx = makeContextFromSource("""
        fun check(range: IntRange, value: Int?): Boolean = range.contains(value)
        fun checkNull(range: IntRange): Boolean = range.contains(null)
        fun checkIn(range: IntRange, value: Int?): Boolean = value in range
        fun checkNotIn(range: IntRange, value: Int?): Boolean = value !in range
        fun checkLong(range: LongRange, value: Long?): Boolean = range.contains(value)
        fun checkChar(range: CharRange, value: Char?): Boolean = range.contains(value)
        fun checkUInt(range: UIntRange, value: UInt?): Boolean = range.contains(value)
        fun checkULong(range: ULongRange, value: ULong?): Boolean = range.contains(value)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        var bindings = 0
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id),
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  let binding = sema.bindings.callBinding(for: id),
                  let symbol = sema.symbols.symbol(binding.chosenCallee),
                  ctx.interner.resolve(symbol.name) == "contains"
            else { continue }
            let signature = try #require(sema.symbols.functionSignature(for: symbol.id))
            #expect(signature.typeParameterSymbols.isEmpty)
            #expect(sema.types.nullability(of: signature.parameterTypes[0]) == .nullable)
            #expect(sema.symbols.isSourceBackedSymbol(symbol.id))
            bindings += 1
        }
        #expect(bindings == 8)
    }

    @Test func allFourUpstreamDeclarationsArePresent() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let symbols = sema.symbols.lookupAll(fqName: ["kotlin", "ranges", "contains"].map(ctx.interner.intern))
        let nullableGenericOverloads = symbols.filter {
            guard let signature = sema.symbols.functionSignature(for: $0),
                  signature.typeParameterSymbols.count == 2,
                  let receiver = signature.receiverType,
                  case .typeParam = sema.types.kind(of: receiver),
                  signature.parameterTypes.count == 1
            else { return false }
            return sema.types.nullability(of: signature.parameterTypes[0]) == .nullable
        }
        #expect(nullableGenericOverloads.count == 4)
        #expect(nullableGenericOverloads.allSatisfy { sema.symbols.isSourceBackedSymbol($0) })
        let collectionContains = sema.symbols.lookupAll(fqName: ["kotlin", "collections", "contains"].map(ctx.interner.intern))
        #expect(collectionContains.contains { candidate in
            sema.symbols.functionSignature(for: candidate)?.typeParameterSymbols.contains { parameter in
                sema.symbols.annotations(for: parameter).contains { $0.annotationFQName == "kotlin.internal.OnlyInputTypes" }
            } == true
        })
    }

    @Test func rangeOnlyReceiverAndWrongElementTypeAreRejected() throws {
        for source in [
            "fun bad(range: ClosedRange<Int>): Boolean = range.contains(null)",
            "fun <T, R> bad(range: R, value: T?): Boolean where T : Comparable<T>, R : ClosedRange<T> { return range.contains(value) }",
            "fun bad(range: IntRange, value: String?): Boolean = range.contains(value)",
            "fun bad(range: IntRange, value: String?): Boolean = value in range"
        ] {
            let ctx = makeContextFromSource(source)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "\(source)")
            #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0009" })
        }
    }

    @Test func genericClosedAndOpenIterableReceiversResolveNullableExtensions() throws {
        let ctx = makeContextFromSource("""
        fun <T, R> closed(range: R, element: T?): Boolean where T : Comparable<T>, R : ClosedRange<T>, R : Iterable<T> {
            return range.contains(element)
        }
        fun <T, R> open(range: R, element: T?): Boolean where T : Comparable<T>, R : OpenEndRange<T>, R : Iterable<T> {
            return element in range
        }
        fun test(range: IntRange): Boolean = closed(range, null)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        var bindings = 0
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id),
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  let binding = sema.bindings.callBinding(for: id),
                  let symbol = sema.symbols.symbol(binding.chosenCallee),
                  ctx.interner.resolve(symbol.name) == "contains"
            else { continue }
            #expect(symbol.fqName.map(ctx.interner.resolve) == ["kotlin", "ranges", "contains"])
            #expect(sema.symbols.functionSignature(for: symbol.id)?.typeParameterSymbols.count == 2)
            bindings += 1
        }
        #expect(bindings == 2)
    }

    @Test func viableMemberStillShadowsExtension() throws {
        let ctx = makeContextFromSource("""
        class Box {
            operator fun contains(value: Int?): Boolean = true
        }
        operator fun Box.contains(value: Int?): Boolean = false
        fun explicit(box: Box, value: Int?): Boolean = box.contains(value)
        fun implicit(box: Box, value: Int?): Boolean = value in box
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        var bindings = 0
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id),
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  let binding = sema.bindings.callBinding(for: id),
                  let symbol = sema.symbols.symbol(binding.chosenCallee),
                  ctx.interner.resolve(symbol.name) == "contains"
            else { continue }
            #expect(symbol.fqName.map(ctx.interner.resolve) == ["Box", "contains"])
            bindings += 1
        }
        #expect(bindings == 2)
    }

    @Test func genericExtensionBodiesCallRangeMemberInsteadOfRecursing() throws {
        let ctx = makeContextFromSource("fun main() {}")
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let declarations = sema.symbols.allSymbols().filter { symbol in
            symbol.fqName.map(ctx.interner.resolve) == ["kotlin", "ranges", "contains"]
                && sema.symbols.functionSignature(for: symbol.id)?.typeParameterSymbols.count == 2
        }
        #expect(declarations.count == 4)
        var memberCalls = 0
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id),
                  declarations.contains(where: { $0.declSite?.contains(range) == true }),
                  let binding = sema.bindings.callBinding(for: id),
                  ctx.interner.resolve(sema.symbols.symbol(binding.chosenCallee)?.name ?? ctx.interner.intern("")) == "contains"
            else { continue }
            let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
            let owner = try #require(sema.symbols.parentSymbol(for: symbol.id))
            let ownerName = try #require(sema.symbols.symbol(owner)).fqName.map(ctx.interner.resolve)
            #expect(ownerName == ["kotlin", "ranges", "ClosedRange"] || ownerName == ["kotlin", "ranges", "OpenEndRange"])
            #expect(sema.symbols.isSourceBackedSymbol(symbol.id))
            #expect(symbol.flags.contains(.extensionMemberAlias) == false)
            #expect(sema.symbols.functionSignature(for: symbol.id)?.classTypeParameterCount == 1)
            if ownerName.last == "OpenEndRange" {
                #expect(sema.symbols.externalLinkName(for: symbol.id) == runtimeABIName(.rangeContains))
            }
            memberCalls += 1
        }
        #expect(memberCalls == 4)
    }

    @Test func smartcastNullableLongGetsNarrowedKIRCopy() throws {
        let ctx = makeContextFromSource("""
        fun consume(value: Long): Long = value
        fun check(value: Long?): Long {
            if (value != null) return consume(value)
            return 0L
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let function = try findKIRFunction(named: "check", in: module, interner: ctx.interner)
        let hasNarrowedCopy = function.body.contains { instruction in
            guard case let .copy(from, to) = instruction,
                  let sourceType = module.arena.exprType(from),
                  let targetType = module.arena.exprType(to)
            else { return false }
            return sourceType == sema.types.makeNullable(sema.types.longType)
                && targetType == sema.types.longType
        }
        #expect(hasNarrowedCopy)
    }
}
#endif
