import Foundation

/// Selects a different clip at each boundary; a single available clip repeats.
struct IdleSequence {
    let clips: [Clip]
    private var previousFile: String?

    init(clips: [Clip]) { self.clips = clips }

    mutating func next(excluding file: String? = nil) -> Clip? {
        let candidates = clips.filter { $0.file != (file ?? previousFile) }
        let clip = (candidates.isEmpty ? clips : candidates).randomElement()
        previousFile = clip?.file
        return clip
    }
}
