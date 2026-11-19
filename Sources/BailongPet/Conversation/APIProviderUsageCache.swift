import Foundation

struct APIProviderUsageCache {
    let provider:APIProviderIdentity
    let usage:DailyTokenUsage
    let fetchedAt:Date
    let generation:Int

    func reusable(provider:APIProviderIdentity,generation:Int,enabled:Bool,seconds:TimeInterval,
                  now:Date = Date(),calendar:Calendar = .current) -> DailyTokenUsage? {
        guard enabled,self.provider == provider,self.generation == generation,usage.usage != nil,
              calendar.isDate(fetchedAt,inSameDayAs:now) else {return nil}
        let age = now.timeIntervalSince(fetchedAt)
        guard age >= 0,age < seconds else {return nil}
        return usage
    }
}
