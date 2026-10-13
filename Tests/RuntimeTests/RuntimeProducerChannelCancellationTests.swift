import Foundation
@testable import Runtime
import Testing

@Suite(.serialized)
struct RuntimeProducerChannelCancellationTests {
    @Test(arguments: [false, true])
    func cancellingClosedChannelDiscardsBufferAndPreservesCloseCause(explicitCause: Bool) {
        let channel = RuntimeChannelHandle(capacity: 1)
        #expect(channel.send(7) == .success)
        let cause = explicitCause ? runtimeAllocateCancellationException(message: "first close") : 0
        #expect(channel.close(cause: cause))
        #expect(!channel.cancel(cause: runtimeAllocateCancellationException(message: "later cancel")))
        var value = 0
        #expect(channel.tryReceive(outValue: &value) == .closed)
        #expect(channel.closeCauseSnapshot() == cause)
    }

    @Test
    func closedChannelThrowingOperationsPreserveOriginalCause() {
        let channel = RuntimeChannelHandle(capacity: 1)
        let cause = runtimeAllocateCancellationException(message: "original cause")
        #expect(channel.close(cause: cause))
        let pointer = Unmanaged.passRetained(channel).toOpaque()
        defer { Unmanaged<RuntimeChannelHandle>.fromOpaque(pointer).release() }
        var thrown = 0
        _ = kk_channel_receive(Int(bitPattern: pointer), 0, nil, &thrown)
        #expect(thrown == cause)
        thrown = 0
        _ = kk_channel_send(Int(bitPattern: pointer), 9, 0, &thrown)
        #expect(thrown == cause)
    }

    @Test(arguments: [false, true], [false, true])
    func cancellingReceiveChannelStopsItsProducer(alreadyClosed: Bool, explicitCause: Bool) {
        let channel = RuntimeChannelHandle(capacity: 1)
        let job = RuntimeJobHandle()
        job.markStarted()
        let scope = RuntimeCoroutineScope()
        scope.adoptJob(job)
        channel.bindProducerScope(scope)
        let pointer = Unmanaged.passRetained(channel).toOpaque()
        defer {
            _ = job.cancel()
            _ = job.complete(with: 0)
            Unmanaged<RuntimeChannelHandle>.fromOpaque(pointer).release()
        }
        if alreadyClosed { #expect(channel.close()) }
        let cause = explicitCause
            ? runtimeAllocateCancellationException(message: "stop producer")
            : runtimeNullSentinelInt

        #expect(__kk_channel_cancel(Int(bitPattern: pointer), cause) == (alreadyClosed ? 0 : 1))
        #expect(job.cancellationSnapshot())
        #expect(scope.isCancelled)
        if explicitCause { #expect(job.cancellationCauseSnapshot() == cause) }
    }
}
