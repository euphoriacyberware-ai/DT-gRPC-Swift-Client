import DrawThingsKit
import DrawThingsQueue
import SwiftUI

/// The running job with its progress and preview, pending jobs (drag to reorder, swipe to
/// cancel) and finished jobs. Rebuilds DrawThingsKit 2.2's `QueueView` on `GenerationQueue`.
struct QueueView: View {
    let queue: GenerationQueue

    var body: some View {
        List {
            if queue.isPaused {
                Section {
                    Label(queue.pauseReason ?? "Paused", systemImage: "pause.circle")
                        .foregroundStyle(.orange)
                }
            }
            if let job = queue.current {
                Section("Running") {
                    RunningJobRow(job: job, queue: queue)
                }
            }
            if !queue.pending.isEmpty {
                Section("Pending (\(queue.pending.count))") {
                    ForEach(queue.pending) { job in
                        JobRow(job: job)
                    }
                    .onMove { queue.movePending(fromOffsets: $0, toOffset: $1) }
                    .onDelete { offsets in
                        offsets.map { queue.pending[$0].id }.forEach { queue.cancel($0) }
                    }
                }
            }
            if !queue.finished.isEmpty {
                Section("Finished") {
                    ForEach(queue.finished.reversed()) { job in
                        JobRow(job: job)
                            .swipeActions {
                                if queue.canRetry(job.id) {
                                    Button("Retry") { queue.retry(job.id) }.tint(.blue)
                                }
                                Button("Remove", role: .destructive) { queue.remove(job.id) }
                            }
                    }
                }
            }
        }
        .overlay {
            if queue.jobs.isEmpty {
                ContentUnavailableView("No jobs", systemImage: "tray", description: Text("Generated jobs appear here."))
            }
        }
        .navigationTitle("Queue")
        .toolbar {
            if queue.isPaused {
                Button("Resume", systemImage: "play.fill") { queue.resume() }
            } else {
                Button("Pause", systemImage: "pause.fill") { queue.pause() }
            }
            Button("Cancel All", systemImage: "xmark.circle") { queue.cancelAll() }
                .disabled(queue.current == nil && queue.pending.isEmpty)
            Button("Clear Finished", systemImage: "trash") { queue.clearFinished() }
                .disabled(queue.finished.isEmpty)
        }
    }
}

struct RunningJobRow: View {
    let job: QueueJob
    let queue: GenerationQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(job.name).font(.headline)
                Spacer()
                Button("Cancel", systemImage: "xmark.circle.fill") { queue.cancel(job.id) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            if let download = queue.remoteDownload {
                ProgressView(value: download.fractionCompleted ?? 0) { Text("Downloading models") }
            } else {
                ProgressView(value: queue.progress?.fractionCompleted ?? 0) {
                    Text(queue.progress?.stage.description ?? "Starting")
                }
            }
            if let preview = queue.preview {
                ResultImage(image: preview).frame(maxHeight: 200)
            }
        }
    }
}

struct JobRow: View {
    let job: QueueJob

    var body: some View {
        HStack {
            if let image = job.result?.images.first {
                ResultImage(image: image).frame(width: 48, height: 48)
            }
            VStack(alignment: .leading) {
                Text(job.name).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private var detail: String {
        switch job.status {
        case .pending: return job.request.configuration.model
        case .running: return "Running"
        case .completed:
            let count = job.result?.images.count ?? 0
            let video = job.result?.media.isVideo == true ? "\(count) frames" : "\(count) image\(count == 1 ? "" : "s")"
            return "\(video) in \(job.duration.map { Duration.seconds($0).formatted(.units(allowed: [.minutes, .seconds])) } ?? "?")"
        case .failed: return "Failed: \(job.error?.localizedDescription ?? "unknown error")"
        case .cancelled: return "Cancelled"
        }
    }
}
