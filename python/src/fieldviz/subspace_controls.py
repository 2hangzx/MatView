"""N-D selection controls placed before the existing plotting controls."""
from PySide6.QtCore import Signal
from PySide6.QtWidgets import QWidget, QFormLayout, QLabel, QLineEdit

from .subspace import selection_for
from .widgets import NumberControl


class SubspaceControls(QWidget):
    changed = Signal(object, object)
    failed = Signal(str)

    def __init__(self):
        super().__init__()
        self.form = QFormLayout(self)
        self.form.setContentsMargins(0, 0, 0, 0)
        self.signature = None
        self.extra_controls = {}

    def configure(self, state, options):
        self.state, self.options = state, options
        target = state.source_handle.target
        signature = (target.shape, state.retained_dimensions, options.retained_dimensions,
                     tuple(sorted((options.extra_indices or {}).items())))
        if signature != self.signature:
            while self.form.rowCount():
                self.form.removeRow(0)
            self.signature = signature
            hint = QLabel(f"原始形状：{target.shape}\n保留 2 或 3 个维度，其余维度固定索引（从 1 开始）。")
            hint.setWordWrap(True)
            self.form.addRow(hint)
            self.retained_edit = QLineEdit(", ".join(map(str, state.retained_dimensions)))
            self.retained_edit.setToolTip("递增的原数组维度编号，例如 1, 2, 3 或 2, 4。")
            self.retained_edit.setReadOnly(options.retained_dimensions is not None)
            self.retained_edit.editingFinished.connect(self._retained_edited)
            self.form.addRow("保留维度", self.retained_edit)
            self.extra_controls = {}
            for dimension, index in state.extra_indices.items():
                if dimension in (options.extra_indices or {}):
                    self.form.addRow(f"Dim {dimension}", QLabel(f"{index}（调用参数固定）"))
                    continue
                control = NumberControl(1, target.shape[dimension - 1], index, integer=True)
                control.changed.connect(lambda v, d=dimension: self._extra_changed(d, int(v)))
                self.extra_controls[dimension] = control
                self.form.addRow(f"Dim {dimension} 索引", control)
        self.indices = dict(state.extra_indices)
        self.retained_edit.setText(", ".join(map(str, state.retained_dimensions)))
        for dimension, control in self.extra_controls.items():
            control.set_value(self.indices[dimension])

    def _retained_edited(self):
        try:
            dimensions = tuple(int(d.strip()) for d in self.retained_edit.text().split(","))
            if dimensions == self.state.retained_dimensions:
                return
            indices = {d: i for d, i in self.indices.items() if d not in dimensions}
            indices.update(self.options.extra_indices or {})
            dimensions, indices = selection_for(self.state.source_handle.target, dimensions, indices)
            self.changed.emit(dimensions, indices)
        except ValueError as exc:
            self.retained_edit.setText(", ".join(map(str, self.state.retained_dimensions)))
            self.failed.emit(str(exc))

    def _extra_changed(self, dimension, index):
        self.indices[dimension] = index
        self.changed.emit(self.state.retained_dimensions, dict(self.indices))
