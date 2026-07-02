import Foundation

struct SyntheticStubSkipStats {
    var skippedCount = 0
    private var skippedSamples: [(owner: String, name: String, arity: Int)] = []

    mutating func recordSkip(
        ownerFQName: [InternedString],
        name: InternedString,
        arity: Int,
        interner: StringInterner
    ) {
        skippedCount += 1
        guard skippedSamples.count < 20 else { return }
        let owner = ownerFQName.map { interner.resolve($0) }.joined(separator: ".")
        skippedSamples.append((owner: owner, name: interner.resolve(name), arity: arity))
    }

    func logIfEnabled() {
        guard ProcessInfo.processInfo.environment["KSWIFTK_DEBUG_STDLIB_STUB_SKIP"] == "1",
              skippedCount > 0
        else {
            return
        }
        FileHandle.standardError.write(
            Data("skipped \(skippedCount) synthetic stub(s) due to bundled Kotlin source\n".utf8)
        )
        for sample in skippedSamples {
            FileHandle.standardError.write(
                Data("  skip: \(sample.owner).\(sample.name)(arity=\(sample.arity))\n".utf8)
            )
        }
        if skippedCount > skippedSamples.count {
            FileHandle.standardError.write(
                Data("  ... and \(skippedCount - skippedSamples.count) more\n".utf8)
            )
        }
    }
}

final class SyntheticStubSkipStatsCollector {
    private var stats = SyntheticStubSkipStats()

    func recordSkip(
        ownerFQName: [InternedString],
        name: InternedString,
        arity: Int,
        interner: StringInterner
    ) {
        stats.recordSkip(
            ownerFQName: ownerFQName,
            name: name,
            arity: arity,
            interner: interner
        )
    }

    func logIfEnabled() {
        stats.logIfEnabled()
    }
}

func shouldSkipSyntheticStub(
    bundledIndex: BundledDeclarationIndex,
    ownerFQName: [InternedString],
    name: InternedString,
    arity: Int
) -> Bool {
    bundledIndex.contains(ownerFQName: ownerFQName, name: name, arity: arity)
}
