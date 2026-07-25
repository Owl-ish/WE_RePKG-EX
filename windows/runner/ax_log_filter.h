#ifndef RUNNER_AX_LOG_FILTER_H_
#define RUNNER_AX_LOG_FILTER_H_

// Drops one specific Flutter engine log line from stderr, passing everything
// else through untouched.
//
// The Windows embedder's accessibility bridge floods stderr whenever a
// scrollable scrolls and an assistive-technology client is attached:
//
//   [ERROR:flutter/shell/platform/common/accessibility_bridge.cc(114)]
//   Failed to update ui::AXTree, error: 280 will not be in the tree ...
//
// Nothing breaks; the engine just logs about semantics nodes that were dropped
// before their parent heard about it. It is an open upstream bug,
// https://github.com/flutter/flutter/issues/182444.
//
// TEMPORARY. Delete this file, its entry in CMakeLists.txt and the call in
// main.cpp once the upstream fix lands.
//
// Call once, early in wWinMain and after any console setup. Does nothing when
// stderr has nowhere to go, which is the case for a release build launched
// without a console.
void InstallAXTreeLogFilter();

#endif  // RUNNER_AX_LOG_FILTER_H_
