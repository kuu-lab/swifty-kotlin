package kotlinx.coroutines

public abstract class MainCoroutineDispatcher : CoroutineDispatcher() {
    public abstract val immediate: MainCoroutineDispatcher
}
