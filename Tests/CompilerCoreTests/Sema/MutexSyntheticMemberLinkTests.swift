#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct MutexSyntheticMemberLinkTests {

    private func externalLinks(
        for member: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> [String] {
        let fq = ["kotlinx", "coroutines", "sync", "Mutex", member].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fq).compactMap { sema.symbols.externalLinkName(for: $0) }
    }

    @Test
    func testMutexSyntheticMemberLinkTestsInventory() throws {
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

            // === testMutexMembersHaveCorrectExternalLinks ===
            do {

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
    }

}
#endif
