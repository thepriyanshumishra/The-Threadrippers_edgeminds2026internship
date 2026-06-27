# app/core/exceptions.py
from typing import List

class DepsRequiredException(Exception):
    def __init__(self, deps: List[str], message: str = "Additional dependencies required"):
        self.deps = deps
        self.message = message
        super().__init__(message)
