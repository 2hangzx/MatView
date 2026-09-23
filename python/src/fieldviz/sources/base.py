"""Source interfaces and opaque, escaped paths (never evaluated as Python code)."""
from abc import ABC, abstractmethod
from urllib.parse import quote


def join_key(parent, name):
    component = quote(str(name), safe="")
    return f"{parent}/{component}" if parent else component


class DataSource(ABC):
    kind = "unknown"
    name = ""
    automatic_target = False

    @abstractmethod
    def list_targets(self):
        pass

    @abstractmethod
    def open_target(self, key):
        pass

    def resolve_key(self, key):
        keys = {target.key for target in self.list_targets()}
        if key in keys:
            return key
        # Convenience only: literal dictionary keys containing dots take precedence.
        alternate = key.replace(".", "/").lstrip("/")
        if alternate in keys:
            return alternate
        raise KeyError(f"不存在或不可绘制的目标: {key}")

    def refresh(self):
        """Return an up-to-date source; memory snapshots deliberately return themselves."""
        return self

    def close(self):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


class FileSource(DataSource):
    def refresh(self):
        from . import open_source
        return open_source(self.name)
