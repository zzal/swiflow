// Tests/SwiflowTests/HMR/HMRTestSupport.swift
//
// Shared test helper that drives the PRODUCTION HMR restore path instead of
// the deleted `HMRWalker.applyRestore` duplicate. `HMRWalker.applyRestore`
// and `wireState(on:scheduler:)` had zero production callers — the diff
// mounts through `wireStateAndRestore`, looking up the snapshot state map via
// `HMRRestoreInstall.stateFor?(path, typeName, key)` (see Diff.swift
// ~239-243). This helper reproduces that exact lookup so the HMR test suite
// exercises the same codepath production runs, rather than a copy that can
// silently drift from it.

import Testing
@testable import Swiflow

/// Look up the snapshot state map for `component` at `(path, key)` the same
/// way the diff's `HMRRestoreInstall.stateFor` closure does, then apply it
/// through the production `wireStateAndRestore` restore pass. `scheduler` is
/// always nil here — these tests only exercise restore, not owner wiring.
@MainActor
func applyHMRRestore(
    index: [SnapshotKey: [String: Any]],
    to component: AnyComponent,
    at path: String,
    key: String?
) {
    let typeName = String(reflecting: type(of: component.instance))
    let stateMap = index[SnapshotKey(path: path, typeName: typeName, key: key)]
    wireStateAndRestore(on: component, scheduler: nil, stateMap: stateMap, path: path)
}
