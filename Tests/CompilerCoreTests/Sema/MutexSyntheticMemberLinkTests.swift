#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct MutexSyntheticMemberLinkTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        let semaResult = try #require(result)
        Self._sharedSema = semaResult
        return semaResult
    }

    private func externalLinks(
        for member: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> [String] {
        let fq = ["kotlinx", "coroutines", "sync", "Mutex", member].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fq).compactMap { sema.symbols.externalLinkName(for: $0) }
    }

    @Test func testMutexMembersHaveCorrectExternalLinks() throws {
        let (sema, interner) = try sharedSema()

        // KSP-677: the wrapper layer (Mutex factory, tryLock, isLocked,
        // withLock) is Kotlin source; only the c-soft kernel primitives
        // remain as synthetic members.
        let expectations: [(member: String, link: String)] = [
            ("lock", "kk_mutex_lock"),
            ("unlock", "kk_mutex_unlock"),
        ]

        for expectation in expectations {
            let links = externalLinks(for: expectation.member, sema: sema, interner: interner)
            #expect(
                links.contains(expectation.link),
                "Mutex.\(expectation.member)() stub missing"
            )
        }
    }
}
#endif
