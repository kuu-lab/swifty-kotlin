@testable import CompilerCore
import Testing

@Suite
struct SemaCacheContextTests {
    // MARK: - Scope Lookup Cache

    @Test func testScopeLookupCacheReturnsSameResultAsUncached() {
        let setup = makeSemaModule()
        let interner = setup.interner
        let symbols = setup.symbols

        let fooName = interner.intern("foo")
        let sym = symbols.define(
            kind: .function, name: fooName,
            fqName: [interner.intern("test"), interner.intern("foo")],
            declSite: nil, visibility: .public, flags: []
        )

        let scope = BaseScope(parent: nil, symbols: symbols)
        scope.insert(sym)

        let cache = SemaCacheContext()
        let uncachedResult = scope.lookup(fooName)
        let cachedResult = cache.lookupInScope(fooName, scope: scope)

        #expect(uncachedResult == cachedResult, "Cached scope lookup must return the same result as uncached")

        // Second call should return the same result (from cache)
        let cachedResult2 = cache.lookupInScope(fooName, scope: scope)
        #expect(cachedResult == cachedResult2, "Repeated cached lookup must be stable")
    }

    @Test func testScopeLookupCacheReturnsEmptyForUnknownName() {
        let setup = makeSemaModule()
        let interner = setup.interner

        let scope = BaseScope(parent: nil, symbols: setup.symbols)
        let cache = SemaCacheContext()

        let result = cache.lookupInScope(interner.intern("nonexistent"), scope: scope)
        #expect(result.isEmpty)
    }

    // MARK: - Symbol Lookup Cache

    @Test func testSymbolLookupCacheReturnsSameResultAsUncached() {
        let setup = makeSemaModule()
        let interner = setup.interner
        let symbols = setup.symbols

        let sym = symbols.define(
            kind: .function, name: interner.intern("fn"),
            fqName: [interner.intern("test"), interner.intern("fn")],
            declSite: nil, visibility: .public, flags: []
        )

        let cache = SemaCacheContext()
        let uncached = symbols.symbol(sym)
        let cached = cache.symbol(sym, in: symbols)

        #expect(uncached?.id == cached?.id)
        #expect(uncached?.kind == cached?.kind)

        // Second call
        let cached2 = cache.symbol(sym, in: symbols)
        #expect(cached?.id == cached2?.id)
    }

    @Test func testSymbolLookupCacheReturnsNilForInvalidID() {
        let setup = makeSemaModule()
        let cache = SemaCacheContext()

        let invalidID = SymbolID(rawValue: 9999)
        let result = cache.symbol(invalidID, in: setup.symbols)
        #expect(result == nil)

        // Second call should also return nil (miss cache)
        let result2 = cache.symbol(invalidID, in: setup.symbols)
        #expect(result2 == nil)
    }

    // MARK: - Call Resolution Cache

    @Test func testCallResolutionCacheReturnsSameResultAsUncached() {
        let setup = makeSemaModule()
        let interner = setup.interner
        let symbols = setup.symbols
        let types = setup.types

        let intType = types.make(.primitive(.int, .nonNull))

        let fn = symbols.define(
            kind: .function, name: interner.intern("add"),
            fqName: [interner.intern("test"), interner.intern("add")],
            declSite: nil, visibility: .public, flags: []
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 0, end: 10),
            calleeName: interner.intern("add"),
            args: [CallArg(type: intType)]
        )

        // Resolve without cache
        let resolverNoCache = OverloadResolver()
        let uncached = resolverNoCache.resolveCall(
            candidates: [fn], call: call, expectedType: intType, ctx: setup.ctx
        )

        // Resolve with cache
        let resolverWithCache = OverloadResolver()
        let cache = SemaCacheContext()
        resolverWithCache.cacheContext = cache
        let cached = resolverWithCache.resolveCall(
            candidates: [fn], call: call, expectedType: intType, ctx: setup.ctx
        )

        // Verify identical results
        #expect(uncached.chosenCallee == cached.chosenCallee)
        #expect(uncached.substitutedTypeArguments == cached.substitutedTypeArguments)
        #expect(uncached.parameterMapping == cached.parameterMapping)
        #expect(uncached.diagnostic == cached.diagnostic)

        // Second call should be a cache hit
        let cached2 = resolverWithCache.resolveCall(
            candidates: [fn], call: call, expectedType: intType, ctx: setup.ctx
        )
        #expect(cached.chosenCallee == cached2.chosenCallee)
        #expect(cached.parameterMapping == cached2.parameterMapping)
        #expect(cache.callResolutionHits == 1, "Second call should be a cache hit")
        #expect(cache.callResolutionMisses == 1, "First call should be a cache miss")
    }

    @Test func testCallResolutionCacheKeyDistinguishesDifferentCandidates() {
        let setup = makeSemaModule()
        let interner = setup.interner
        let symbols = setup.symbols
        let types = setup.types

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))

        let fnA = symbols.define(
            kind: .function, name: interner.intern("f"),
            fqName: [interner.intern("test"), interner.intern("fA")],
            declSite: nil, visibility: .public, flags: []
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType),
            for: fnA
        )

        let fnB = symbols.define(
            kind: .function, name: interner.intern("f"),
            fqName: [interner.intern("test"), interner.intern("fB")],
            declSite: nil, visibility: .public, flags: []
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: boolType),
            for: fnB
        )

        let call = CallExpr(
            range: makeRange(start: 10, end: 20),
            calleeName: interner.intern("f"),
            args: [CallArg(type: intType)]
        )

        let resolver = OverloadResolver()
        let cache = SemaCacheContext()
        resolver.cacheContext = cache

        let resultA = resolver.resolveCall(
            candidates: [fnA], call: call, expectedType: nil, ctx: setup.ctx
        )
        let resultB = resolver.resolveCall(
            candidates: [fnB], call: call, expectedType: nil, ctx: setup.ctx
        )

        // Different candidates should produce different results
        #expect(resultA.chosenCallee == fnA)
        #expect(resultB.chosenCallee == fnB)
        #expect(cache.callResolutionMisses == 2, "Different candidate sets must be separate cache entries")
    }

    // MARK: - Differential Verification (cache ON vs OFF produce same diagnostics)

    @Test func testCallResolutionCachePreservesIntegerLiteralValues() {
        let setup = makeSemaModule()
        let name = setup.interner.intern("narrow")
        let fn = setup.symbols.define(
            kind: .function, name: name, fqName: [name],
            declSite: nil, visibility: .public, flags: []
        )
        setup.symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [setup.types.byteType], returnType: setup.types.byteType),
            for: fn
        )
        let resolver = OverloadResolver()
        let cache = SemaCacheContext()
        resolver.cacheContext = cache
        for value: Int64 in [127, 128] {
            let call = CallExpr(
                range: makeRange(start: 10, end: 20), calleeName: name,
                args: [CallArg(type: setup.types.intType, signedIntegerLiteral: value)]
            )
            let result = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: setup.ctx)
            #expect((result.chosenCallee == fn) == (value == 127))
        }
        let variableCall = CallExpr(
            range: makeRange(start: 20, end: 30), calleeName: name,
            args: [CallArg(type: setup.types.intType)]
        )
        let result = resolver.resolveCall(candidates: [fn], call: variableCall, expectedType: nil, ctx: setup.ctx)
        #expect(result.chosenCallee == nil)
        #expect(cache.callResolutionMisses == 3)
        #expect(cache.callResolutionHits == 0)
    }

    @Test func testDifferentialVerificationSimpleFunction() throws {
        let source = """
        fun add(a: Int, b: Int): Int = a + b
        fun main() {
            val result = add(1, 2)
        }
        """

        // Without cache
        let ctxNoCache = makeContextFromSource(source)
        try runSema(ctxNoCache)
        let diagsNoCache = ctxNoCache.diagnostics.diagnostics

        // With cache
        let ctxCached = makeContextFromSource(source, frontendFlags: ["sema-cache"])
        try runSema(ctxCached)
        let diagsCached = ctxCached.diagnostics.diagnostics

        #expect(
            diagsNoCache.map(\.code).sorted() == diagsCached.map(\.code).sorted(),
            "Diagnostic codes must be identical with and without sema-cache"
        )
    }
}
