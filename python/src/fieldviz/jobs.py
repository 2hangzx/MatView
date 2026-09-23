"""One running task + one replaceable pending task, never an unbounded drag queue."""
from concurrent.futures import ThreadPoolExecutor

from PySide6.QtCore import QObject, Signal, Slot


class LatestJob(QObject):
    result = Signal(object)
    failed = Signal(str)
    busy_changed = Signal(bool)
    _finished = Signal(int, object, object)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="fieldviz")
        self._generation = 0
        self._running = False
        self._pending = None
        self._closed = False
        self._finished.connect(self._complete)

    @property
    def busy(self):
        return self._running or self._pending is not None

    def invalidate(self):
        self._generation += 1
        self._pending = None

    def submit(self, function):
        if self._closed:
            return
        self._generation += 1
        self._pending = (self._generation, function)
        self.busy_changed.emit(True)
        if not self._running:
            self._start()

    def _start(self):
        generation, function = self._pending
        self._pending = None
        self._running = True
        future = self._executor.submit(function)

        def finished(task):
            try:
                value, error = task.result(), None
            except Exception as exc:
                value, error = None, exc
            # The QObject may already be destroyed when a long native call finishes.
            if not self._closed:
                try:
                    self._finished.emit(generation, value, error)
                except RuntimeError:
                    pass
        future.add_done_callback(finished)

    @Slot(int, object, object)
    def _complete(self, generation, value, error):
        self._running = False
        if self._closed:
            return
        if generation == self._generation:
            if error is None:
                self.result.emit(value)
            else:
                self.failed.emit(str(error))
        if self._pending is not None and not self._running:
            self._start()
        else:
            self.busy_changed.emit(self.busy)

    def close(self):
        self._closed = True
        self.invalidate()
        self._executor.shutdown(wait=False, cancel_futures=True)
