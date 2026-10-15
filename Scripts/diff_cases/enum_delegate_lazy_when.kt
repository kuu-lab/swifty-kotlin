// KUU-2201: delegated storage fields must not be counted as enum entries.
// Reproduces KT-68339 from JetBrains/kotlin v2.3.10.
enum class State {
    STARTED, STOPPED;

    val label by lazy {
        when (this) {
            STARTED -> "started"
            STOPPED -> "stopped"
        }
    }

    val explicitLabel by lazy {
        val state: State = this
        when (state) {
            State.STARTED -> "started"
            State.STOPPED -> "stopped"
        }
    }

    fun labelFromMemberFunction() = when (this) {
        STARTED -> "started"
        STOPPED -> "stopped"
    }
}

class OtherOwner {
    val label by lazy {
        when (State.STARTED) {
            State.STARTED -> "started"
            State.STOPPED -> "stopped"
        }
    }
}

val topLevelLabel by lazy {
    when (State.STARTED) {
        State.STARTED -> "started"
        State.STOPPED -> "stopped"
    }
}

fun main() {
    println(State.STARTED.label)
    println(State.STOPPED.label)
    println(State.STARTED.explicitLabel)
    println(State.STOPPED.explicitLabel)
    println(State.values().size)
    println(State.entries.size)
    println(State.STARTED.labelFromMemberFunction())
    println(OtherOwner().label)
    println(topLevelLabel)
}
