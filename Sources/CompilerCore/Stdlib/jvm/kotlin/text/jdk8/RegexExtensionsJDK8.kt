package kotlin.text.jdk8
import kotlin.text.*
operator fun MatchGroupCollection.get(name: String): MatchGroup? = namedGroup(this, name)
