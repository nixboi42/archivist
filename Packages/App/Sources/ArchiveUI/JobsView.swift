import ArchiveApplication
import SwiftUI

public struct JobsView: View {
    @ObservedObject private var model: ArchiveAppModel
    public init(model: ArchiveAppModel) { self.model = model }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Jobs").font(.headline).padding()
            Divider()
            if model.jobs.isEmpty { ContentUnavailableView("No Jobs", systemImage: "clock") }
            else {
                List(model.jobs) { job in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(job.descriptor.kind.rawValue.capitalized).fontWeight(.medium); Spacer(); Text(stateName(job.state)).foregroundStyle(.secondary) }
                        Text(job.descriptor.sourceURLs.first?.lastPathComponent ?? "Archive operation").lineLimit(1).foregroundStyle(.secondary)
                        if let progress = job.latestProgress {
                            if let fraction = progress.fractionCompleted { ProgressView(value: fraction) } else if job.state == .running { ProgressView() }
                            if let path = progress.currentEntryPath { Text(path).font(.caption).lineLimit(1) }
                        }
                        HStack {
                            Spacer()
                            if job.state == .running || job.state == .queued { Button("Cancel") { model.cancelJob(job.id) } }
                            if job.state.isRetryable { Button("Retry") { model.retryJob(job.id) } }
                        }
                    }.padding(.vertical, 4).accessibilityElement(children: .combine)
                }
            }
        }.frame(width: 340, height: 380)
    }
}

private func stateName(_ state: JobState) -> String {
    switch state { case .queued: "Queued"; case .running: "Running"; case .completed: "Completed"; case .failed: "Failed"; case .cancelled: "Cancelled" }
}
private extension JobState { var isRetryable: Bool { if case .failed = self { return true }; return self == .cancelled } }
