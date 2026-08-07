#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct SemaphoreSyntheticMemberLinkTests {

    private func externalLinks(
        for member: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> [String] {
        let fq = ["kotlinx", "coroutines", "sync", "Semaphore", member].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fq).compactMap { sema.symbols.externalLinkName(for: $0) }
    }

    @Test
    func testSemaphoreSyntheticMemberLinkTestsInventory() throws {
        let sources: [String] = [
            """
            fun noop() {}
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx

            // === testSemaphoreMembersHaveCorrectExternalLinks ===
            do {

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
    }

}
#endif
