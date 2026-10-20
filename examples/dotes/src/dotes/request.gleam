/// Identity of an asynchronous request and the screen/form that issued it.
pub type Id {
  Id(sequence: Int, screen: Int, revision: Int)
}

/// Initial screen's load request.
pub fn new() -> Id {
  Id(0, 0, 0)
}

/// Start a newer request, or consume a completed request exactly once.
pub fn next(id: Id) -> Id {
  Id(..id, sequence: id.sequence + 1)
}

/// Navigation invalidates results even when returning to the same note.
pub fn navigate(id: Id) -> Id {
  Id(id.sequence + 1, id.screen + 1, 0)
}

/// A changed draft must not be cleared by an older write result.
pub fn revise(id: Id) -> Id {
  Id(..id, revision: id.revision + 1)
}
