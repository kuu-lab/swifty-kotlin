// KUU-3928: a smart cast established inside an `else` branch must survive a
// later flow split in the same branch. `ctx.flowState` is a snapshot taken at
// the branch entry, so a second `branchOnCondition`-based split (a contract
// call like `check`/`requireNotNull`, or a plain `if`) rebuilt its base from
// the stale pre-narrowing entry and `applyFlowStateToLocals` overwrote the
// local's refined type — `source.position = position` then reported
// SEMA-0022 on a perfectly valid member. Mirrors okio FileHandle.kt.

interface Source
class RealBufferedSource(val source: Source, val buffer: Long) : Source

abstract class FileHandle {
    // Same-named member functions shadow nothing: the receiver's member
    // property must still win on qualified access.
    fun position(source: Source): Long = -1
    fun size(source: Source): Long = -1

    private class FileHandleSource(
        val fileHandle: FileHandle,
        var position: Long,
        var closed: Boolean = false
    ) : Source

    fun source(position: Long): Source = FileHandleSource(this, position)

    fun reposition(source: Source, position: Long) {
        if (source is RealBufferedSource) {
            val fileHandleSource = source.source
            require(fileHandleSource is FileHandleSource && fileHandleSource.fileHandle === this) { "bad" }
            fileHandleSource.position = position
        } else {
            require(source is FileHandleSource && source.fileHandle === this) { "bad" }
            check(!source.closed) { "closed" }
            source.position = position
        }
    }

    fun readPosition(source: Source): Long {
        require(source is FileHandleSource) { "bad" }
        return source.position
    }

    // Second contract flavour: `returns() implies` resolves through the
    // `.normally` implication path rather than the condition branch.
    fun repositionNotNull(source: Source, position: Long, token: Any?) {
        if (source is RealBufferedSource) {
        } else {
            require(source is FileHandleSource) { "bad" }
            requireNotNull(token)
            source.position = position
        }
    }

    // A plain `if` split must preserve the narrowed type the same way.
    fun repositionIf(source: Source, position: Long) {
        if (source is RealBufferedSource) {
        } else {
            require(source is FileHandleSource) { "bad" }
            if (source.closed) {
                source.position = -1
            }
            source.position = position
        }
    }
}

class Handle : FileHandle()

fun main() {
    val handle = Handle()

    val plain = handle.source(7)
    handle.reposition(plain, 42)
    println(handle.readPosition(plain))

    val buffered = handle.source(1)
    handle.reposition(RealBufferedSource(buffered, 0), 11)
    println(handle.readPosition(buffered))

    val viaNotNull = handle.source(3)
    handle.repositionNotNull(viaNotNull, 5, "token")
    println(handle.readPosition(viaNotNull))

    val viaIf = handle.source(9)
    handle.repositionIf(viaIf, 13)
    println(handle.readPosition(viaIf))
}
