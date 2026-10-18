import Foundation

public final class PhaseTimer {
    public struct PhaseRecord {
        public let name: String
        public let startTime: UInt64
        public let endTime: UInt64
        public let subRecords: [PhaseRecord]

        /// Sum of disjoint invocation durations for an accumulated record.
        /// Its timestamps span the first through last invocation, including gaps.
        public let accumulatedDurationNanos: UInt64?

        public var durationNanos: UInt64 {
            accumulatedDurationNanos ?? (endTime - startTime)
        }

        public var durationMs: Double {
            Double(durationNanos) / 1_000_000.0
        }

        public init(
            name: String, startTime: UInt64, endTime: UInt64,
            subRecords: [PhaseRecord] = [], accumulatedDurationNanos: UInt64? = nil
        ) {
            self.name = name
            self.startTime = startTime
            self.endTime = endTime
            self.subRecords = subRecords
            self.accumulatedDurationNanos = accumulatedDurationNanos
        }
    }

    private var records: [PhaseRecord] = []
    private var currentPhaseName: String?
    private var currentPhaseStart: UInt64 = 0
    private var currentSubRecords: [PhaseRecord] = []

    private struct SubPhase {
        let name: String
        let startTime: UInt64
        var records: [PhaseRecord] = []
    }

    private var subPhaseStack: [SubPhase] = []
    private var accumulatedRecords: [PhaseRecord] = []
    private var activeAccumulations: Set<String> = []

    public init() {}

    public func beginPhase(_ name: String) {
        currentPhaseName = name
        currentPhaseStart = DispatchTime.now().uptimeNanoseconds
        currentSubRecords = []
        subPhaseStack = []
        accumulatedRecords = []
        activeAccumulations = []
    }

    public func endPhase() {
        guard let name = currentPhaseName else { return }
        let endTime = DispatchTime.now().uptimeNanoseconds
        records.append(PhaseRecord(
            name: name,
            startTime: currentPhaseStart,
            endTime: endTime,
            subRecords: currentSubRecords + accumulatedRecords
        ))
        currentPhaseName = nil
        currentSubRecords = []
        accumulatedRecords = []
    }

    public func recordSubPhase(_ name: String, startTime: UInt64, endTime: UInt64) {
        appendSubRecord(PhaseRecord(name: name, startTime: startTime, endTime: endTime))
    }


    private func appendSubRecord(_ record: PhaseRecord) {
        guard currentPhaseName != nil else { return }
        if subPhaseStack.isEmpty {
            currentSubRecords.append(record)
        } else {
            subPhaseStack[subPhaseStack.count - 1].records.append(record)
        }
    }

    private func appendAccumulatedRecord(name: String, startTime: UInt64, endTime: UInt64, duration: UInt64) {
        if let index = accumulatedRecords.firstIndex(where: { $0.name == name }) {
            let previous = accumulatedRecords[index]
            accumulatedRecords[index] = PhaseRecord(
                name: name, startTime: previous.startTime,
                endTime: endTime, accumulatedDurationNanos: previous.durationNanos + duration
            )
        } else {
            accumulatedRecords.append(PhaseRecord(
                name: name, startTime: startTime, endTime: endTime,
                accumulatedDurationNanos: duration
            ))
        }
    }

    /// Measure a scope, including work completed before an error is thrown.
    /// Accumulated scopes are reported once under the active top-level phase;
    /// recursive invocations of the same scope are included only once.
    /// They overlap other inclusive scopes and are not added to TOTAL.
    fileprivate func measure<Result>(
        _ name: String,
        accumulating: Bool,
        attributingAccumulationToCurrentSubPhase: Bool = false,
        _ body: () throws -> Result
    ) rethrows -> Result {
        guard currentPhaseName != nil else { return try body() }
        if accumulating {
            guard activeAccumulations.insert(name).inserted else { return try body() }
            let attributedName = attributingAccumulationToCurrentSubPhase
                ? subPhaseStack.last.map { "\(name).\($0.name)" }
                : nil
            let start = DispatchTime.now().uptimeNanoseconds
            defer {
                let end = DispatchTime.now().uptimeNanoseconds
                let duration = end - start
                activeAccumulations.remove(name)
                appendAccumulatedRecord(name: name, startTime: start, endTime: end, duration: duration)
                if let attributedName {
                    appendAccumulatedRecord(
                        name: attributedName, startTime: start, endTime: end, duration: duration
                    )
                }
            }
            return try body()
        }
        subPhaseStack.append(SubPhase(name: name, startTime: DispatchTime.now().uptimeNanoseconds))
        defer {
            let scope = subPhaseStack.removeLast()
            appendSubRecord(PhaseRecord(
                name: scope.name, startTime: scope.startTime,
                endTime: DispatchTime.now().uptimeNanoseconds, subRecords: scope.records
            ))
        }
        return try body()
    }


    /// Measure synchronous work on the pipeline thread. With no timer, avoid
    /// reading the clock. Failed operations still contribute a timing record.
    public static func measureSubPhase<T>(
        _ name: String,
        timer: PhaseTimer?,
        _ body: () throws -> T
    ) rethrows -> T {
        guard let timer else { return try body() }
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            timer.recordSubPhase(name, startTime: start, endTime: DispatchTime.now().uptimeNanoseconds)
        }
        return try body()
    }

    public var phaseRecords: [PhaseRecord] {
        records
    }

    public var totalNanos: UInt64 {
        records.reduce(0) { $0 + $1.durationNanos }
    }

    public var totalMs: Double {
        Double(totalNanos) / 1_000_000.0
    }


    /// Pad `text` without truncating labels needed to identify individual passes.
    private func pad(_ text: String, to width: Int) -> String {
        text + String(repeating: " ", count: max(0, width - text.count))
    }

    public func printSummary() {
        FileHandle.standardError.write(Data(summary().utf8))
    }

    func summary() -> String {
        let total = totalMs
        func labelWidth(_ record: PhaseRecord, depth: Int) -> Int {
            max(record.name.count + depth * 2,
                record.subRecords.map { labelWidth($0, depth: depth + 1) }.max() ?? 0)
        }
        let width = max(24, records.map { labelWidth($0, depth: 0) }.max() ?? 0)
        let separator = String(repeating: "-", count: width + 22) + "\n"
        var output = "===== Phase Timing Summary =====\n"
        output += "\(pad("Phase", to: width)) \(pad("Time (ms)", to: 10)) \(pad("%", to: 8))\n"
        output += separator
        func append(_ record: PhaseRecord, depth: Int) {
            let label = String(repeating: " ", count: depth * 2) + record.name
            let pct = total > 0 ? record.durationMs / total * 100 : 0
            output += "\(pad(label, to: width)) \(String(format: "%10.2f", record.durationMs)) \(String(format: "%7.1f%%", pct))\n"
            for child in record.subRecords { append(child, depth: depth + 1) }
        }
        for record in records { append(record, depth: 0) }
        output += separator
        output += "\(pad("TOTAL", to: width)) \(String(format: "%10.2f", total)) \(String(format: "%7.1f%%", 100.0))\n"
        return output
    }
}

/// Avoid clock reads, label construction and timing storage when timing is disabled.
package func withSubPhaseTiming<Result>(
    _ name: @autoclosure () -> String,
    timer: PhaseTimer?,
    accumulating: Bool = false,
    attributingAccumulationToCurrentSubPhase: Bool = false,
    _ body: () throws -> Result
) rethrows -> Result {
    guard let timer else { return try body() }
    return try timer.measure(
        name(), accumulating: accumulating,
        attributingAccumulationToCurrentSubPhase: attributingAccumulationToCurrentSubPhase,
        body
    )
}
