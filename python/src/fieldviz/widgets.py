"""Small reusable UI primitives: precise edits, coalesced sliders and safe colorbars."""
import math

import numpy as np
from PySide6.QtCore import Qt, Signal, QSize, QRectF
from PySide6.QtGui import QColor, QLinearGradient, QPainter, QDoubleValidator
from PySide6.QtWidgets import QWidget, QHBoxLayout, QLineEdit, QSlider, QSizePolicy, QGridLayout


class NumberControl(QWidget):
    """A full-precision text edit paired with a coarse slider; no decimal truncation."""
    changed = Signal(float)

    def __init__(self, low, high, value, *, integer=False, slider=True, allow_outside=False, parent=None):
        super().__init__(parent)
        self.low, self.high, self.integer = float(low), float(high), integer
        self.value = float(value)
        self.allow_outside = allow_outside
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(12)
        self.edit = QLineEdit()
        self.edit.setMinimumWidth(95)
        self.edit.setMaximumWidth(145)
        self.edit.setValidator(QDoubleValidator(self.edit))
        self.edit.editingFinished.connect(self._edited)
        layout.addWidget(self.edit)
        self.slider = QSlider(Qt.Orientation.Horizontal)
        self.slider.setRange(0, 10000)
        self.slider.setMinimumWidth(95)
        self.slider.setVisible(slider)
        self.slider.valueChanged.connect(self._slid)
        layout.addWidget(self.slider, 1)
        self.set_value(value)

    def set_bounds(self, low, high):
        self.low, self.high = float(low), float(high)
        self.set_value(self.value)

    def set_value(self, value):
        self.value = float(value)
        self.edit.setText(format(self.value, ".10g"))
        self.edit.setToolTip(format(self.value, ".17g"))
        self.slider.blockSignals(True)
        ratio = (self.value - self.low) / (self.high - self.low) if self.high > self.low else 0
        self.slider.setValue(int(round(min(1, max(0, ratio)) * 10000)))
        self.slider.setEnabled(self.high > self.low)
        self.slider.blockSignals(False)

    def _edited(self):
        if self.edit.text() == format(self.value, ".10g"):
            return  # Do not round the underlying value merely because the edit lost focus.
        try:
            value = float(self.edit.text())
            if not math.isfinite(value) or (not self.allow_outside and not self.low <= value <= self.high):
                raise ValueError
            if self.integer and value != round(value):
                raise ValueError
        except ValueError:
            self.set_value(self.value)
            return
        self.set_value(value)
        self.changed.emit(value)

    def _slid(self, position):
        value = self.low + (self.high - self.low) * position / 10000
        if self.integer:
            value = round(value)
        if value != self.value:
            self.set_value(value)
            self.changed.emit(value)


class AdaptiveGrid(QWidget):
    """Reflow complete control groups; scrolling handles short windows, never clipping."""
    def __init__(self):
        super().__init__()
        self.grid = QGridLayout(self)
        self.grid.setContentsMargins(12, 12, 12, 20)
        self.grid.setSpacing(12)
        self.items = []
        self.columns = 0

    def add_group(self, widget):
        self.items.append(widget)

    def reflow(self):
        columns = max(1, self.width() // 340)
        while self.grid.count():
            self.grid.takeAt(0)
        visible = [w for w in self.items if not w.isHidden()]
        for i, widget in enumerate(visible):
            self.grid.addWidget(widget, i // columns, i % columns)
        for col in range(max(columns, self.columns)):
            self.grid.setColumnStretch(col, int(col < columns))
        self.columns = columns
        self.setMinimumHeight(self.grid.sizeHint().height())

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.reflow()


class ColorBar(QWidget):
    """Colorbar owns its label margin; plot resizing cannot clip numeric annotations."""
    def __init__(self, colors, parent=None):
        super().__init__(parent)
        self.colors = colors
        self.limits = (0.0, 1.0)
        self.setMinimumHeight(180)
        self.setSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Expanding)
        self.set_limits(self.limits)

    def set_limits(self, limits):
        self.limits = tuple(limits)
        ticks = np.linspace(*limits, 6)
        for precision in range(8, 18):
            self.labels = [format(x, f".{precision}g") for x in ticks]
            if len(set(self.labels)) == len(set(ticks)):
                break
        width = max(self.fontMetrics().horizontalAdvance(s) for s in self.labels + ["Value"])
        self.setFixedWidth(width + 52)
        self.update()

    def sizeHint(self):
        return QSize(self.minimumWidth(), 300)

    def paintEvent(self, event):
        painter = QPainter(self)
        metrics = painter.fontMetrics()
        top, bottom = 30.0, float(self.height() - metrics.height() - 12)
        gradient = QLinearGradient(0, bottom, 0, top)
        for i, color in enumerate(self.colors):
            gradient.setColorAt(i / (len(self.colors) - 1), QColor(*map(int, color[:3])))
        painter.fillRect(QRectF(6, top, 22, bottom - top), gradient)
        painter.setPen(QColor("#313844"))
        painter.drawRect(QRectF(6, top, 22, bottom - top))
        painter.drawText(6, 17, "Value")
        for i, label in enumerate(self.labels):
            y = bottom - i * (bottom - top) / 5
            painter.drawLine(28, round(y), 32, round(y))
            painter.drawText(37, round(y + metrics.ascent() / 2 - 1), label)
