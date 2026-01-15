import Foundation

actor TokenBucket {
    private var tokens: Double
    private let capacity: Double
    private let refillRate: Double // bytes per second
    private var lastRefillTime: Date
    
    init(capacity: Int64, refillRateBytesPerSecond: Int64) {
        self.capacity = Double(capacity)
        self.refillRate = Double(refillRateBytesPerSecond)
        self.tokens = Double(capacity)
        self.lastRefillTime = Date()
    }
    
    func requestTokens(amount: Int) async {
        while true {
            refillTokens()
            
            if tokens >= Double(amount) {
                tokens -= Double(amount)
                return
            }
            
            let needed = Double(amount) - tokens
            let waitTime = needed / refillRate
            
            if waitTime > 0 {
                try? await Task.sleep(nanoseconds: UInt64(min(waitTime, 0.1) * 1_000_000_000))
            }
        }
    }
    
    func tryConsumeTokens(amount: Int) -> Bool {
        refillTokens()
        if tokens >= Double(amount) {
            tokens -= Double(amount)
            return true
        }
        return false
    }
    
    private func refillTokens() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefillTime)
        let tokensToAdd = elapsed * refillRate
        tokens = min(capacity, tokens + tokensToAdd)
        lastRefillTime = now
    }
    
    func updateRate(bytesPerSecond: Int64) {
        // This will change the refill rate dynamically
    }
    
    var availableTokens: Double {
        refillTokens()
        return tokens
    }
}

@MainActor
class SpeedLimiter: ObservableObject {
    static let shared = SpeedLimiter()
    
    @Published var isEnabled: Bool = false
    @Published var limitBytesPerSecond: Int64 = 0
    
    private var bucket: TokenBucket?
    
    private init() {}
    
    func setLimit(bytesPerSecond: Int64) {
        if bytesPerSecond > 0 {
            isEnabled = true
            limitBytesPerSecond = bytesPerSecond
            // Capacity = 2 seconds worth of data for burst allowance
            bucket = TokenBucket(capacity: bytesPerSecond * 2, refillRateBytesPerSecond: bytesPerSecond)
        } else {
            isEnabled = false
            limitBytesPerSecond = 0
            bucket = nil
        }
    }
    
    func disableLimit() {
        isEnabled = false
        limitBytesPerSecond = 0
        bucket = nil
    }
    
    func requestPermissionToTransfer(bytes: Int) async {
        guard isEnabled, let bucket = bucket else { return }
        await bucket.requestTokens(amount: bytes)
    }
    
    var limitDescription: String {
        guard isEnabled, limitBytesPerSecond > 0 else { return "Unlimited" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: limitBytesPerSecond))/s"
    }
}
