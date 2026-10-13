# Atomicfu private runtime kernel contract (prepared)

These eight private entries support actual bundled atomicfu 0.33.0 source.
All machine words are `intptr_t` on the supported 64-bit target. Kotlin Long
nanoseconds are unboxed signed words. `-1` alone denotes infinite waiting; other
negative finite values behave as zero. Kotlin converts negative/zero Duration to
zero and positive infinity to -1. Deadlines use DispatchTime's monotonic clock
with saturating addition, not wall time.

| Symbol | Complete C signature | Throwing / result | §13-2 reason |
| --- | --- | --- | --- |
| `__kk_atomicfu_lock_new` | `intptr_t __kk_atomicfu_lock_new(intptr_t ownerErrorKind);` | nonthrowing; registered actual recursive-lock kernel; 1=IAE, 0=ISE | syscall, memory representation |
| `__kk_atomicfu_lock_lock` | `intptr_t __kk_atomicfu_lock_lock(intptr_t kernel, intptr_t * _Nullable outThrown);` | throwing; Unit word 0 after actual acquisition | syscall |
| `__kk_atomicfu_lock_try_lock` | `intptr_t __kk_atomicfu_lock_try_lock(intptr_t kernel, intptr_t timeoutNanos, intptr_t * _Nullable outThrown);` | throwing; raw Boolean 0/1 (registered ABI returnsRawBoolean=true) | syscall |
| `__kk_atomicfu_lock_unlock` | `intptr_t __kk_atomicfu_lock_unlock(intptr_t kernel, intptr_t * _Nullable outThrown);` | throwing; Unit 0; wrong owner gets configured IAE/ISE | syscall |
| `__kk_atomicfu_parker_new` | `intptr_t __kk_atomicfu_parker_new(void);` | nonthrowing; registered actual parker owned by creating thread | syscall, memory representation |
| `__kk_atomicfu_parker_wait` | `intptr_t __kk_atomicfu_parker_wait(intptr_t kernel, intptr_t timeoutNanos, intptr_t * _Nullable outThrown);` | throwing; Unit 0 on permit/wake/timeout; wrong thread ISE | syscall |
| `__kk_atomicfu_parker_unpark` | `intptr_t __kk_atomicfu_parker_unpark(intptr_t kernel, intptr_t * _Nullable outThrown);` | throwing; Unit 0; callable by any thread | syscall |
| `__kk_atomicfu_current_parking_handle` | `intptr_t __kk_atomicfu_current_parking_handle(intptr_t fnPtr, intptr_t closureRaw, intptr_t * _Nullable outThrown);` | throwing; cached ordinary Kotlin ParkingHandle result | GC/TLS, memory representation |

Throwing entries zero outThrown before use, write an actual typed Kotlin
exception and return `runtimeExceptionCaughtSentinel` on failure. Invalid/wrong
kind handles yield IllegalArgumentException. A missing exception destination is
the Runtime's uncaught fatal path. The exact private link is routed through the existing Function0 thunk adapter
by CallLowerer: noncapturing and captured raw callables receive the explicit env
word plus their separate lowered outThrown slot; ordinary user homonyms do not
match this route. The factory callback receives its actual
closure environment and outThrown; failures propagate unchanged and are never
cached. No public API receives arbitrary unregistered pointer values.

A kernel is a real Swift object registered in the Runtime's existing object
pointer table. A normal Kotlin `Any` field stores the registered reference; an
ordinary AtomicInt/SynchronizedObject/ParkingHandle wrapper is never cast to a
kernel box or passed as a coroutine Mutex receiver. Registration currently
retains boxes for the Runtime lifetime, as for standard atomic boxes. Ordinary
mark/sweep does not reclaim that registry. This is an explicit existing lifetime
limit, not a claim of per-wrapper garbage collection. Per-thread wrapper cache
roots use the actual global-root registry and are unregistered/deallocated by
the pthread TLS destructor. A handle retained by another thread remains usable
for unpark; it does not become a dangling stack pointer. Unique per-thread
monotonic tokens avoid pthread address reuse impersonating a former lock owner.
Force-reset invalidates cached wrappers by generation and requires all workers
already joined; concurrent resets are unsupported by the existing test runtime.

State transitions are serialized by native NSLock, with blocking work outside
that mutex. Recursive depth belongs to the unique thread token. Zero-time
tryLock neither waits nor barges over a queued waiter. FIFO grants assign
ownership before signalling; a grant racing timeout is accepted rather than
stranding a lock. Cancelled nodes are removed. A parker stores one permit:
repeated pre-unpark coalesces, park consumes the permit even at a nonpositive
finite timeout, and any thread may signal a parked owner. Each waiter uses its
own semaphore, so a wake cannot leak into a future unrelated wait. A completed
unpark detaches its waiter under stateLock before returning. A second completed
unpark, even before the first owner resumes, sets the next permit. Old waiter
cleanup clears only that identical waiter and never clears the new permit.
This matches pinned Native ThreadParker Parked -> Unparking -> Free and the
subsequent Free -> Unparked transition. The internal after-wait test hook is nil
at all Runtime ABI calls and executes outside stateLock; it adds no export. No Kotlin
callback executes while an internal state lock is held.

Prepared direct Runtime tests cover recursion and partial release, wrong owner,
FIFO/timeout cancellation, distinct IAE/ISE contracts, private raw-Boolean ABI,
pre-permit/coalescing/timed wake, wrong-thread park, invalid handles, callback
error propagation, cache identity/reset, completed-wake/second-permit interleaving,
live per-thread root insertion and actual slot-to-handle value, and root removal
on actual thread exit. Ordinary registered boxes survive collection independently
of roots, so that survival is not used as evidence for mark/sweep root protection.
Workers use finite timeouts and a bounded drain before Runtime test isolation ends.
If a worker still fails to terminate, the test process aborts instead of resetting
live workers' Runtime handles. The outer gate must record/reap that process failure.
The enclosing gate must still enforce process-group watchdog/reap on a hang.

Budget change is +8 distinct `__kk_*` cdecls / +0 `kk_*` cdecls; no raw scalar
factory whitelist entry or synthetic atomicfu declaration. specVersion changes
automatically from registered full signatures. Swift syntax parsing is preparation-only validation; neither the new Swift code
nor its tests were typechecked or executed during scratch preparation.
