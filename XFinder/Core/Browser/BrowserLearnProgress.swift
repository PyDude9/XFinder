import Foundation

/// Explicit local completion, independent of filesystem access and presentation order.
enum BrowserLearnProgress {
    static let key = "fileBrowser.learn.completed"
    static let lessonIDs = ["navigation", "tabs", "panes", "metadata", "spaces", "preview"]

    static func completed(in data: Data) -> Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: data)) ?? [])
    }

    static func count(in data: Data) -> Int {
        completed(in: data).intersection(lessonIDs).count
    }

    static func updating(_ data: Data, lesson: String, isComplete: Bool) -> Data {
        guard lessonIDs.contains(lesson) else { return data }
        var values = completed(in: data)
        if isComplete { values.insert(lesson) } else { values.remove(lesson) }
        return (try? JSONEncoder().encode(values.sorted())) ?? data
    }
}
