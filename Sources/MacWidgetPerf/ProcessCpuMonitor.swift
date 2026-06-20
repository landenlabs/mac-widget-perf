// Copyright (c) 2026 LanDen Labs - Dennis Lang
import Foundation

// MARK: - LibProc bindings (no bridging header needed)

private let PROC_ALL_PIDS:  UInt32 = 1
private let PROC_PIDTASKINFO: Int32 = 4

// Mirror of struct proc_taskinfo from <sys/proc_info.h>
// 6 × UInt64 (48 bytes) + 12 × Int32 (48 bytes) = 96 bytes total, no padding on LP64.
private struct ProcTaskInfo {
    var pti_virtual_size:      UInt64 = 0
    var pti_resident_size:     UInt64 = 0
    var pti_total_user:        UInt64 = 0  // nanoseconds of user CPU
    var pti_total_system:      UInt64 = 0  // nanoseconds of system CPU
    var pti_threads_user:      UInt64 = 0
    var pti_threads_system:    UInt64 = 0
    var pti_policy:            Int32  = 0
    var pti_faults:            Int32  = 0
    var pti_pageins:           Int32  = 0
    var pti_cow_faults:        Int32  = 0
    var pti_messages_sent:     Int32  = 0
    var pti_messages_received: Int32  = 0
    var pti_syscalls_mach:     Int32  = 0
    var pti_syscalls_unix:     Int32  = 0
    var pti_csw:               Int32  = 0
    var pti_threadnum:         Int32  = 0
    var pti_numrunning:        Int32  = 0
    var pti_priority:          Int32  = 0
}

@_silgen_name("proc_listpids")
private func libproc_listpids(_ type: UInt32, _ typeinfo: UInt32,
                               _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_pidinfo")
private func libproc_pidinfo(_ pid: Int32, _ flavor: Int32, _ arg: UInt64,
                              _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_name")
private func libproc_name(_ pid: Int32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: UInt32) -> Int32

// MARK: - ProcessCpuMonitor

/// Tracks per-process CPU usage in a rolling window and reports the busiest process
/// by average share of total CPU capacity. Aggregates by process name so all instances
/// of the same app (e.g. multiple "chrome" workers) sum together.
final class ProcessCpuMonitor {

    // One snapshot per sample tick: total nanoseconds each named process burned.
    private struct Snapshot {
        let time:    Date
        let perName: [String: Double]  // name → CPU nanoseconds consumed this interval
    }

    private let lock      = NSLock()
    private var prevNs:   [Int32: UInt64] = [:]   // pid → cumulative CPU ns at last tick
    private var snapshots: [Snapshot]     = []
    private var timer:     Timer?
    private let coreCount: Double

    private static let maxWindowSeconds = 600.0

    init() {
        coreCount = Double(ProcessInfo.processInfo.processorCount)
    }

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        primeSample()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Query

    /// Returns the top process (name, % of total CPU capacity) over the last
    /// `windowSeconds` of the rolling history. Returns nil until the window warms up.
    func topProcess(windowSeconds: Double) -> (name: String, percent: Double)? {
        let cutoff = Date().addingTimeInterval(-windowSeconds)
        var agg: [String: Double] = [:]
        var earliest: Date?

        lock.lock()
        for snap in snapshots where snap.time >= cutoff {
            if earliest == nil { earliest = snap.time }
            for (name, ns) in snap.perName { agg[name, default: 0] += ns }
        }
        lock.unlock()

        guard let earliest, !agg.isEmpty else { return nil }

        let spanSec = max(1.0, Date().timeIntervalSince(earliest))
        let totalCapacityNs = spanSec * coreCount * 1_000_000_000
        guard let top = agg.max(by: { $0.value < $1.value }) else { return nil }
        let pct = min(100.0, top.value / totalCapacityNs * 100.0)
        guard pct >= 0.5 else { return nil }
        return (name: top.key, percent: pct)
    }

    // MARK: - Sampling

    private func primeSample() {
        _ = currentTotals()  // ignore delta, just warm prevNs
    }

    private func sample() {
        let now  = Date()
        let snap = Snapshot(time: now, perName: currentTotals())

        lock.lock()
        snapshots.append(snap)
        let cutoff = now.addingTimeInterval(-ProcessCpuMonitor.maxWindowSeconds)
        while let first = snapshots.first, first.time < cutoff { snapshots.removeFirst() }
        lock.unlock()
    }

    // Reads all PIDs, computes per-name CPU ns delta vs prevNs, updates prevNs.
    private func currentTotals() -> [String: Double] {
        let pids    = allPIDs()
        var current = [Int32: UInt64](minimumCapacity: pids.count)
        var perName = [String: Double]()

        for pid in pids {
            guard pid > 0 else { continue }
            var info = ProcTaskInfo()
            let size = Int32(MemoryLayout<ProcTaskInfo>.size)
            let ret  = withUnsafeMutableBytes(of: &info) { ptr in
                libproc_pidinfo(pid, PROC_PIDTASKINFO, 0, ptr.baseAddress, size)
            }
            guard ret == size else { continue }

            let totalNs = info.pti_total_user + info.pti_total_system
            current[pid] = totalNs

            if let prev = prevNs[pid], totalNs >= prev {
                let delta = Double(totalNs - prev)
                if delta > 0 {
                    let name = processName(pid)
                    perName[name, default: 0] += delta
                }
            }
        }

        prevNs = current
        return perName
    }

    private func allPIDs() -> [Int32] {
        // First call: get required buffer size
        let needed = libproc_listpids(PROC_ALL_PIDS, 0, nil, 0)
        guard needed > 0 else { return [] }
        var buf = [Int32](repeating: 0, count: Int(needed) / MemoryLayout<Int32>.size + 4)
        let filled = buf.withUnsafeMutableBytes { ptr in
            libproc_listpids(PROC_ALL_PIDS, 0, ptr.baseAddress, Int32(ptr.count))
        }
        guard filled > 0 else { return [] }
        let count = Int(filled) / MemoryLayout<Int32>.size
        return Array(buf.prefix(count))
    }

    private func processName(_ pid: Int32) -> String {
        var buf = [CChar](repeating: 0, count: 1024)
        let ret = buf.withUnsafeMutableBytes { ptr in
            libproc_name(pid, ptr.baseAddress, UInt32(ptr.count))
        }
        guard ret > 0 else { return "pid \(pid)" }
        return String(cString: buf)
    }
}
