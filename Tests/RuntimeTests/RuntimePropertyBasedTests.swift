#if canImport(Testing)
import Testing
@testable import Runtime

@Suite
struct RuntimePropertyBasedTests {
    private struct PropertyStats: Equatable {
        let checked: Int
        let failures: Int
        let shrinks: Int
        let minimizedCounterexample: Int?
    }

    // KSP-466: this helper only needs *some* deterministic-per-seed integer
    // sequence to drive this file's own property-based test infrastructure —
    // it has nothing to do with testing kotlin.random.Random itself (which is
    // now real Kotlin source, not backed by SeededRandomBox). Using
    // SeededRandomBox directly (still `@testable`-visible; it survives as
    // SecureRandom's internal PRNG) instead of the deleted
    // kk_random_create_seeded/kk_random_nextLong bridge keeps the exact same
    // sequence this file always generated.
    private func seededSamples(seed: Int, count: Int) -> [Int] {
        let random = SeededRandomBox(seed: seed)
        return (0..<count).map { _ in random.nextFullInt() }
    }

    private func shrinkTowardZero(_ value: Int) -> Int? {
        guard value != 0 else {
            return nil
        }
        let next = value / 2
        return next == value ? nil : next
    }

    private func runPropertyCheck(
        samples: [Int],
        predicate: (Int) -> Bool
    ) -> PropertyStats {
        var checked = 0
        var shrinks = 0

        for sample in samples {
            checked += 1
            if predicate(sample) {
                continue
            }

            var current = sample
            var minimized = sample

            while let next = shrinkTowardZero(current), next != current {
                if predicate(next) {
                    break
                }
                shrinks += 1
                minimized = next
                current = next
            }

            return PropertyStats(
                checked: checked,
                failures: 1,
                shrinks: shrinks,
                minimizedCounterexample: minimized
            )
        }

        return PropertyStats(
            checked: checked,
            failures: 0,
            shrinks: 0,
            minimizedCounterexample: nil
        )
    }

    @Test
    func testPropertyCheckReportsSuccessAcrossGeneratedSamples() {
        let samples = seededSamples(seed: 42, count: 32)
        let stats = runPropertyCheck(samples: samples) { sample in
            sample + 0 == sample
        }

        #expect(stats.checked == 32)
        #expect(stats.failures == 0)
        #expect(stats.shrinks == 0)
        #expect(stats.minimizedCounterexample == nil)
    }

    @Test
    func testPropertyCheckShrinksCounterexamplesTowardZero() {
        let samples = [13] + seededSamples(seed: 31415, count: 15).map { abs($0 % 17) * 2 + 1 }
        let stats = runPropertyCheck(samples: samples) { sample in
            sample == 0
        }

        #expect(stats.checked == 1)
        #expect(stats.failures == 1)
        #expect(stats.shrinks == 3)
        #expect(stats.minimizedCounterexample == 1)
    }

    @Test
    func testSeededSampleGenerationIsDeterministic() {
        let samplesA = seededSamples(seed: 2026, count: 8)
        let samplesB = seededSamples(seed: 2026, count: 8)
        let samplesC = seededSamples(seed: 2027, count: 8)

        #expect(samplesA == samplesB)
        #expect(samplesA != samplesC)
    }
}
#endif
