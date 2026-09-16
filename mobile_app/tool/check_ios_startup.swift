// Runs on the macOS CI host, not inside the app. Reject a launch screen or a
// SpringBoard screenshot: both home-page labels must be visibly rendered.
import Foundation
import Vision
import Darwin

guard CommandLine.arguments.count == 2 else { exit(2) }
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["zh-Hans", "en-US"]
let handler = VNImageRequestHandler(url: URL(fileURLWithPath: CommandLine.arguments[1]))
do {
    try handler.perform([request])
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    print(text)
    let normalized = text.components(separatedBy: .whitespacesAndNewlines).joined()
    exit(normalized.contains("设备记录") && normalized.contains("历史记录") ? 0 : 1)
} catch {
    fputs("Screenshot recognition failed: \(error)\n", stderr)
    exit(2)
}
