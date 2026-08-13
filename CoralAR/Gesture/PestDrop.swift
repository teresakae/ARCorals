import simd

/// Pure release-distance check for pest pick-up-and-throw (docs/GESTURES.md pest content, §3
/// `GestureTuning.pestDiscardDistance`). True → released far enough from O1 to fade & delete;
/// false → accidental near-drop, leave the pest exactly where it landed.
func shouldDiscardPest(
    releaseWorldPosition: SIMD3<Float>,
    anchorWorldPosition: SIMD3<Float>,
    discardDistance: Float
) -> Bool {
    simd_distance(releaseWorldPosition, anchorWorldPosition) > discardDistance
}
