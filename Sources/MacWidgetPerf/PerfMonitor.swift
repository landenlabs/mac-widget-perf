// Copyright (c) 2026 LanDen Labs - Dennis Lang
import Foundation
import Darwin
import IOKit

// MARK: - PerfSample

struct PerfSample {
    var cpu:     Double = 0  // 0..100 %
    var disk:    Double = 0  // bytes/sec combined read+write
    var netDown: Double = 0  // bytes/sec
    var netUp:   Double = 0  // bytes/sec
}

// MARK: - PerfMonitor

final class PerfMonitor: ObservableObject {

    // Published sample history (normalized values 0..1 for chart)
    @Published var cpuSamples:     [Double] = []
    @Published var diskSamples:    [Double] = []
    @Published var netDownSamples: [Double] = []

    // Current raw values for legend display
    @Published var currentCpu:     Double = 0
    @Published var currentDisk:    Double = 0  // bytes/sec
    @Published var currentNetDown: Double = 0  // bytes/sec

    // Learned peaks for auto-scaling
    @Published var diskPeak:    Double = 1
    @Published var netDownPeak: Double = 1

    // Top process over the rolling window
    @Published var topProcessName:    String? = nil
    @Published var topProcessPercent: Double  = 0

    private let processCpuMonitor = ProcessCpuMonitor()
    private var timer:            Timer?
    private(set) var sampleInterval:  Double = 1.0
    private(set) var maxSamples:      Int    = 120
    private(set) var historySeconds:  Double = 120.0

    // CPU state
    private var prevCpuUser: UInt64 = 0
    private var prevCpuSys:  UInt64 = 0
    private var prevCpuIdle: UInt64 = 0
    private var prevCpuNice: UInt64 = 0

    // Disk state
    private var prevDiskRead:  UInt64 = 0
    private var prevDiskWrite: UInt64 = 0

    // Network state
    private var prevBytesIn:  UInt64 = 0
    private var prevBytesOut: UInt64 = 0

    // MARK: - Configuration

    func configure(sampleInterval: Double, maxSamples: Int, historySeconds: Double = 120) {
        let changed = self.sampleInterval != sampleInterval || self.maxSamples != maxSamples
        self.sampleInterval  = sampleInterval
        self.maxSamples      = maxSamples
        self.historySeconds  = historySeconds

        if cpuSamples.count > maxSamples {
            cpuSamples     = Array(cpuSamples.suffix(maxSamples))
            diskSamples    = Array(diskSamples.suffix(maxSamples))
            netDownSamples = Array(netDownSamples.suffix(maxSamples))
        }

        if changed && timer != nil { stop(); start() }
    }

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        // Prime counters
        primeCpu()
        primeDisk()
        primeNetwork()
        processCpuMonitor.start()

        if cpuSamples.isEmpty {
            cpuSamples     = Array(repeating: 0, count: maxSamples)
            diskSamples    = Array(repeating: 0, count: maxSamples)
            netDownSamples = Array(repeating: 0, count: maxSamples)
        }

        timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        processCpuMonitor.stop()
    }

    // MARK: - Tick

    private func tick() {
        let cpu     = sampleCpu()
        let disk    = sampleDisk()
        let netDown = sampleNetwork()
        let top     = processCpuMonitor.topProcess(windowSeconds: historySeconds)

        DispatchQueue.main.async { [self] in
            currentCpu     = cpu
            currentDisk    = disk
            currentNetDown = netDown

            topProcessName    = top?.name
            topProcessPercent = top?.percent ?? 0

            diskPeak    = max(diskSamples.max() ?? 1, max(disk, 1))
            netDownPeak = max(netDownSamples.max() ?? 1, max(netDown, 1))

            append(to: &cpuSamples,     value: cpu / 100.0)
            append(to: &diskSamples,    value: disk / diskPeak)
            append(to: &netDownSamples, value: netDown / netDownPeak)
        }
    }

    private func append(to samples: inout [Double], value: Double) {
        samples.append(min(1, max(0, value)))
        if samples.count > maxSamples { samples.removeFirst() }
    }

    // MARK: - CPU

    private func primeCpu() {
        var numCPUs: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                   &numCPUs, &info, &infoCount) == KERN_SUCCESS,
              let ptr = info else { return }
        defer { vm_deallocate(mach_task_self_,
                              vm_address_t(bitPattern: ptr),
                              vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)) }
        var user: UInt64 = 0, sys: UInt64 = 0, idle: UInt64 = 0, nice: UInt64 = 0
        for i in 0..<Int(numCPUs) {
            let base = i * Int(CPU_STATE_MAX)
            user += UInt64(bitPattern: Int64(ptr[base + Int(CPU_STATE_USER)]))
            sys  += UInt64(bitPattern: Int64(ptr[base + Int(CPU_STATE_SYSTEM)]))
            idle += UInt64(bitPattern: Int64(ptr[base + Int(CPU_STATE_IDLE)]))
            nice += UInt64(bitPattern: Int64(ptr[base + Int(CPU_STATE_NICE)]))
        }
        prevCpuUser = user; prevCpuSys = sys; prevCpuIdle = idle; prevCpuNice = nice
    }

    private func sampleCpu() -> Double {
        var numCPUs: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                   &numCPUs, &info, &infoCount) == KERN_SUCCESS,
              let ptr = info else { return 0 }
        defer { vm_deallocate(mach_task_self_,
                              vm_address_t(bitPattern: ptr),
                              vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)) }
        var user: UInt64 = 0, sys: UInt64 = 0, idle: UInt64 = 0, nice: UInt64 = 0
        for i in 0..<Int(numCPUs) {
            let base = i * Int(CPU_STATE_MAX)
            user += UInt64(bitPattern: Int64(ptr[base + Int(CPU_STATE_USER)]))
            sys  += UInt64(bitPattern: Int64(ptr[base + Int(CPU_STATE_SYSTEM)]))
            idle += UInt64(bitPattern: Int64(ptr[base + Int(CPU_STATE_IDLE)]))
            nice += UInt64(bitPattern: Int64(ptr[base + Int(CPU_STATE_NICE)]))
        }
        let dUser = user - prevCpuUser
        let dSys  = sys  - prevCpuSys
        let dIdle = idle - prevCpuIdle
        let dNice = nice - prevCpuNice
        prevCpuUser = user; prevCpuSys = sys; prevCpuIdle = idle; prevCpuNice = nice

        let dTotal = dUser + dSys + dIdle + dNice
        guard dTotal > 0 else { return 0 }
        return min(100.0, Double(dUser + dSys + dNice) / Double(dTotal) * 100.0)
    }

    // MARK: - Disk (IOKit)

    private func readDiskBytes() -> (read: UInt64, write: UInt64) {
        var readTotal:  UInt64 = 0
        var writeTotal: UInt64 = 0

        var iter: io_iterator_t = 0
        // kIOMainPortDefault == 0 on macOS 12+
        guard IOServiceGetMatchingServices(0, IOServiceMatching("IOBlockStorageDriver"), &iter) == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service) }
            var propsRef: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = propsRef?.takeRetainedValue() as? [String: Any],
               let stats = dict["Statistics"] as? [String: Any] {
                readTotal  += stats["Bytes (Read)"]    as? UInt64 ?? 0
                writeTotal += stats["Bytes (Written)"] as? UInt64 ?? 0
            }
            service = IOIteratorNext(iter)
        }
        return (readTotal, writeTotal)
    }

    private func primeDisk() {
        let (r, w) = readDiskBytes()
        prevDiskRead = r; prevDiskWrite = w
    }

    private func sampleDisk() -> Double {
        let (r, w) = readDiskBytes()
        let dRead  = r >= prevDiskRead  ? r - prevDiskRead  : 0
        let dWrite = w >= prevDiskWrite ? w - prevDiskWrite : 0
        prevDiskRead = r; prevDiskWrite = w
        return Double(dRead + dWrite) / sampleInterval
    }

    // MARK: - Network (getifaddrs)

    private func totalNetBytes() -> (UInt64, UInt64) {
        var bytesIn: UInt64 = 0, bytesOut: UInt64 = 0
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let cur = ptr {
            let ifa  = cur.pointee
            let name = String(cString: ifa.ifa_name)
            if ifa.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
               !name.hasPrefix("lo"),
               let data = ifa.ifa_data {
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                bytesIn  += UInt64(stats.ifi_ibytes)
                bytesOut += UInt64(stats.ifi_obytes)
            }
            ptr = ifa.ifa_next
        }
        return (bytesIn, bytesOut)
    }

    private func primeNetwork() {
        let (i, o) = totalNetBytes()
        prevBytesIn = i; prevBytesOut = o
    }

    private func sampleNetwork() -> Double {
        let (curIn, _) = totalNetBytes()
        let dlRate = curIn >= prevBytesIn ? Double(curIn - prevBytesIn) / sampleInterval : 0
        prevBytesIn = curIn
        return dlRate
    }
}
