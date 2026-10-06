import Testing
@testable import ScanLabCore

@Suite struct ThermalPolicyTests {
    @Test("FR-3.8 thermal actions", arguments: [
        (ThermalLevel.nominal, ThermalAction.proceed),
        (.fair, .proceed),
        (.serious, .warn),
        (.critical, .saveAndStop),
    ])
    func action(level: ThermalLevel, expected: ThermalAction) {
        #expect(ThermalPolicy.action(for: level) == expected)
    }
}
