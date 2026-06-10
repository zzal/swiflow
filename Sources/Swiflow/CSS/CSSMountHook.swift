// Sources/Swiflow/CSS/CSSMountHook.swift
//
// Module-level hook that SwiflowDOM sets to receive a notification
// each time a Component type is first mounted. This follows the same
// pattern as `HMRRestoreInstall.stateFor` in HMR.swift: a nullable
// closure that the WASM layer wires up at startup without creating a
// direct dependency from the pure-Swift module to JavaScriptKit.

public nonisolated(unsafe) var onComponentTypeMount: ((any Component.Type) -> Void)?
