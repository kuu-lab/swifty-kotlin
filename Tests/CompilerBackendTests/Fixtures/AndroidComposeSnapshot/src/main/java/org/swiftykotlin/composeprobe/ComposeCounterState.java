package org.swiftykotlin.composeprobe;

import android.widget.TextView;
import androidx.compose.runtime.MutableState;
import androidx.compose.runtime.SnapshotStateKt;
import androidx.compose.runtime.snapshots.Snapshot;
import androidx.compose.runtime.snapshots.SnapshotStateObserver;
import kotlin.Unit;
import kotlin.jvm.functions.Function1;

public final class ComposeCounterState {
    public interface Draw { void render(); }

    public static void setText(TextView view, String text) {
        view.setText(text);
    }

    private final MutableState<Integer> count =
        SnapshotStateKt.mutableStateOf(0, SnapshotStateKt.structuralEqualityPolicy());
    private final SnapshotStateObserver observer = new SnapshotStateObserver(callback -> callback.invoke());
    private final Function1<Draw, Unit> onChanged = draw -> {
        observe(draw);
        return Unit.INSTANCE;
    };

    public ComposeCounterState() {
        observer.start();
    }

    public int value() {
        return count.getValue();
    }

    public void increment() {
        count.setValue(count.getValue() + 1);
        Snapshot.Companion.sendApplyNotifications();
    }

    public void observe(Draw draw) {
        observer.observeReads(draw, onChanged, () -> {
            draw.render();
            return Unit.INSTANCE;
        });
    }

    public void close() {
        observer.stop();
        observer.clear();
    }
}
