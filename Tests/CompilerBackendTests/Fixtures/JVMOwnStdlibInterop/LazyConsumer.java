import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import kotlin.Lazy;
import kotlin.LazyThreadSafetyMode;
import kotlin.LazyKt;

public class LazyConsumer {
    public static void main(String[] args) throws Exception {
        Object lock = new Object();
        AtomicInteger calls = new AtomicInteger();
        Lazy<Object> synchronizedValue = LazyKt.lazy(lock, () -> {
            if (!Thread.holdsLock(lock)) throw new AssertionError("Missing supplied monitor");
            calls.incrementAndGet();
            return new Object();
        });
        if (synchronizedValue.isInitialized()) throw new AssertionError();
        ExecutorService pool = Executors.newFixedThreadPool(16);
        try {
            CountDownLatch start = new CountDownLatch(1);
            List<Future<Object>> results = new ArrayList<>();
            for (int i = 0; i < 64; i++) results.add(pool.submit(() -> { start.await(); return synchronizedValue.getValue(); }));
            start.countDown();
            Object winner = results.get(0).get(10, TimeUnit.SECONDS);
            for (Future<Object> result : results) if (result.get(10, TimeUnit.SECONDS) != winner) throw new AssertionError();
            if (calls.get() != 1 || !synchronizedValue.isInitialized()) throw new AssertionError();
            CountDownLatch entered = new CountDownLatch(16);
            AtomicInteger publishedCalls = new AtomicInteger();
            Lazy<Object> published = LazyKt.lazy(LazyThreadSafetyMode.PUBLICATION, () -> {
                publishedCalls.incrementAndGet(); entered.countDown();
                try { if (!entered.await(10, TimeUnit.SECONDS)) throw new AssertionError("Publication serialized initialization"); }
                catch (InterruptedException error) { throw new AssertionError(error); }
                return new Object();
            });
            results.clear();
            for (int i = 0; i < 16; i++) results.add(pool.submit(() -> published.getValue()));
            winner = results.get(0).get(10, TimeUnit.SECONDS);
            for (Future<Object> result : results) if (result.get(10, TimeUnit.SECONDS) != winner) throw new AssertionError();
            if (publishedCalls.get() != 16) throw new AssertionError();
        } finally { pool.shutdownNow(); }
        for (LazyThreadSafetyMode mode : LazyThreadSafetyMode.values()) {
            AtomicInteger attempts = new AtomicInteger();
            Lazy<String> retry = LazyKt.lazy(mode, () -> {
                if (attempts.incrementAndGet() == 1) throw new IllegalStateException("retry");
                return null;
            });
            try { retry.getValue(); throw new AssertionError(); } catch (IllegalStateException expected) {}
            if (retry.isInitialized()) throw new AssertionError();
            if (retry.getValue() != null || retry.getValue() != null || attempts.get() != 2 || !retry.isInitialized()) throw new AssertionError();
        }
        System.out.println("lazy modes, monitors, publication, retry and null: OK");
    }
}
