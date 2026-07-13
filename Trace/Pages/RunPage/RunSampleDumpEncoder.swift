import Foundation

#if DEBUG
/// 본 러닝 QA에서 회수하는 원시 데이터 덤프(스펙 §1) — 사이클 2 저장 스키마 결정의 근거.
enum RunSampleDumpEncoder {
    struct Dump: Encodable {
        let startedAt: Date
        let entries: [RunSampleDumpEntry]
    }

    static func jsonData(entries: [RunSampleDumpEntry], startedAt: Date) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Dump(startedAt: startedAt, entries: entries))
    }
}
#endif
