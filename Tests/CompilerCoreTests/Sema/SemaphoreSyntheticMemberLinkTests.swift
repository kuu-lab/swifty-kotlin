#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct SemaphoreSyntheticMemberLinkTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try #require(result)
    }

    private func externalLinks(
        for member: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> [String] {
        let fq = ["kotlinx", "coroutines", "sync", "Semaphore", member].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fq).compactMap { sema.symbols.externalLinkName(for: $0) }
    }

    @Test func testSemaphoreMembersHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        // KSP-677: the wrapper layer (Semaphore factory, tryAcquire,
        // availablePermits, withPermit) is Kotlin source; only the c-soft
        // kernel primitives remain as synthetic members.
        let expectations: [(member: String, link: String)] = [
            ("acquire", "kk_semaphore_acquire"),
            ("release", "kk_semaphore_release"),
        ]

        for expectation in expectations {
            let links = externalLinks(for: expectation.member, sema: sema, interner: interner)
            #expect(
                links.contains(expectation.link),
                "Semaphore.\(expectation.member)() stub missing"
            )
        }
    }
}
#endif
