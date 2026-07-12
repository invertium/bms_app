import 'package:bms_dash/bms_state.dart';
import 'package:bms_dash/demo_bms.dart';
import 'package:bms_dash/jbd_bms.dart';
import 'package:flutter_test/flutter_test.dart';

TelemetrySample _sample(int second) => TelemetrySample(
      time: DateTime(2026, 1, 1, 0, 0, second),
      voltage: 40,
      current: -1,
      soc: 50,
      temperature: 22,
    );

void main() {
  group('appendCapped', () {
    test('evicts the oldest samples beyond the cap', () {
      var history = const <TelemetrySample>[];
      for (var i = 0; i < 5; i++) {
        history = appendCapped(history, _sample(i), cap: 3);
      }
      expect(history, hasLength(3));
      expect(history.first.time.second, 2);
      expect(history.last.time.second, 4);
    });
  });

  group('TelemetrySample', () {
    test('derives power and mean temperature from basic info', () {
      const info = JbdBasicInfo(
        totalVoltage: 40,
        current: -2.5,
        remainingCapacityAh: 20,
        nominalCapacityAh: 24,
        cycleCount: 1,
        protectionStatus: 0,
        socPercent: 80,
        chargeFetOn: true,
        dischargeFetOn: true,
        cellCount: 10,
        temperaturesCelsius: [20, 24],
      );
      final sample = TelemetrySample.fromBasicInfo(info, DateTime(2026));
      expect(sample.power, closeTo(-100, 0.001));
      expect(sample.temperature, closeTo(22, 0.001));
      expect(sample.soc, 80);
    });
  });

  group('DemoBmsSession', () {
    test('emits telemetry and mirrors MOSFET state with software lock',
        () async {
      final session = DemoBmsSession();
      addTearDown(session.dispose);

      final first = await session.basicInfo.first
          .timeout(const Duration(seconds: 3));
      expect(first.cellCount, 10);
      expect(first.mosfetsOn, isTrue);
      expect(first.isSoftwareLocked, isFalse);

      final cells = await session.cellVoltages.first
          .timeout(const Duration(seconds: 3));
      expect(cells, hasLength(10));

      final confirmed = session.basicInfo
          .firstWhere((info) => !info.chargeFetOn && !info.dischargeFetOn)
          .timeout(const Duration(seconds: 3));
      await session.setMosfets(chargeOn: false, dischargeOn: false);
      final off = await confirmed;
      expect(off.isSoftwareLocked, isTrue);
      expect(off.hasProtectionFault, isFalse);
      expect(off.current, 0);
    });
  });
}
