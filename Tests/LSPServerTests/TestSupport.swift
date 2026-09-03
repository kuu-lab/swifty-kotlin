import Foundation
@testable import LSPServer

final class MemoryInputStream: ByteInputStream {
    private var chunks: [Data]

    init(_ data: Data) {
        chunks = [data]
    }

    init(chunks: [Data]) {
        self.chunks = chunks
    }

    func readChunk() -> Data {
        chunks.isEmpty ? Data() : chunks.removeFirst()
    }
}

final class MemoryOutputStream: ByteOutputStream {
    private(set) var data = Data()

    func write(_ data: Data) {
        self.data.append(data)
    }
}

final class ManualLSPScheduledTask: LSPScheduledTask, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var operation: (@Sendable () -> Void)?
    private var cancelled = false

    init(operation: @escaping @Sendable () -> Void) {
        self.operation = operation
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func run() {
        lock.lock()
        let operation = cancelled ? nil : self.operation
        self.operation = nil
        lock.unlock()
        operation?()
    }
}

final class ManualLSPDebounceScheduler: LSPDebounceScheduler, @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [ManualLSPScheduledTask] = []

    func schedule(
        after _: DispatchTimeInterval,
        operation: @escaping @Sendable () -> Void
    ) -> any LSPScheduledTask {
        let task = ManualLSPScheduledTask(operation: operation)
        lock.lock()
        tasks.append(task)
        lock.unlock()
        return task
    }

    func runAll() {
        while true {
            lock.lock()
            guard !tasks.isEmpty else {
                lock.unlock()
                return
            }
            let task = tasks.removeFirst()
            lock.unlock()
            task.run()
        }
    }

    @discardableResult
    func runNextAsync() -> DispatchGroup {
        lock.lock()
        let task = tasks.removeFirst()
        lock.unlock()

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            task.run()
            group.leave()
        }
        return group
    }
}

final class LSPAnalysisEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String] = []

    func record(_ event: Analyzer.AnalysisEvent) {
        guard case let .started(_, text) = event else { return }
        lock.lock()
        texts.append(text)
        lock.unlock()
    }

    var startedTexts: [String] {
        lock.lock()
        defer { lock.unlock() }
        return texts
    }
}

final class BlockingLSPAnalysisEvent: @unchecked Sendable {
    private let condition = NSCondition()
    private var startedTexts: [String] = []
    private var completedCount = 0
    private var released = false

    func observe(_ event: Analyzer.AnalysisEvent) {
        condition.lock()
        switch event {
        case let .started(_, text):
            startedTexts.append(text)
            condition.broadcast()
            while !released {
                condition.wait()
            }
        case .completed:
            completedCount += 1
            condition.broadcast()
        }
        condition.unlock()
    }

    func waitUntilStarted() {
        condition.lock()
        while startedTexts.isEmpty {
            condition.wait()
        }
        condition.unlock()
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }

    func waitUntilCompleted() {
        condition.lock()
        while completedCount == 0 {
            condition.wait()
        }
        condition.unlock()
    }

    var analyzedTexts: [String] {
        condition.lock()
        defer { condition.unlock() }
        return startedTexts
    }
}

enum LSPTestSupport {
    static func message(id: Int? = nil, method: String? = nil, params: Any? = nil) -> [String: Any] {
        var message: [String: Any] = ["jsonrpc": "2.0"]
        if let id { message["id"] = id }
        if let method { message["method"] = method }
        if let params { message["params"] = params }
        return message
    }

    static func frame(_ object: [String: Any]) -> Data {
        // swiftlint:disable:next force_try
        let body = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        var framed = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        framed.append(body)
        return framed
    }

    static func frame(_ objects: [[String: Any]]) -> Data {
        var data = Data()
        for object in objects {
            data.append(frame(object))
        }
        return data
    }

    static func decodeMessages(from output: MemoryOutputStream) -> [[String: Any]] {
        let connection = JSONRPCConnection(input: MemoryInputStream(output.data), output: MemoryOutputStream())
        var messages: [[String: Any]] = []
        while let message = connection.receive() {
            messages.append(message)
        }
        return messages
    }

    /// Returns the 0-based (line, UTF-16 character) position of the first
    /// occurrence of `needle` in `text`.
    static func position(of needle: String, in text: String) -> (line: Int, character: Int)? {
        guard let range = text.range(of: needle) else { return nil }
        let prefix = text[text.startIndex ..< range.lowerBound]
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        let line = lines.count - 1
        let lastLine = lines.last ?? ""
        return (line: line, character: lastLine.utf16.count)
    }
}
