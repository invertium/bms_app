import 'dart:async';
import 'dart:math';

import 'jbd_bms.dart';

/// A synthetic 10S battery implementing [BmsSession], so every connected
/// screen can be exercised without hardware (e.g. on an emulator without
/// Bluetooth).
///
/// The simulation drifts between charging and discharging, keeps a
/// persistent small cell imbalance with jitter, balances the highest cells
/// while charging, and mirrors the real BMS's software-lock protection bit
/// when the MOSFETs are switched off.
class DemoBmsSession implements BmsSession {
  DemoBmsSession({Random? random}) : _random = random ?? Random(7) {
    // Persistent per-cell offsets so the same cells stay high/low across
    // ticks, like a real pack.
    _cellOffsets = List.generate(
      _cellCount,
      (_) => (_random.nextDouble() - 0.4) * 0.024,
    );
    _timer = Timer.periodic(_tickInterval, (_) => _tick());
    // Deliver the first sample soon after "connecting" instead of waiting a
    // full tick.
    Timer(const Duration(milliseconds: 400), _tick);
  }

  static const Duration _tickInterval = Duration(seconds: 2);
  static const int _cellCount = 10;
  static const double _nominalAh = 24.0;

  final Random _random;
  late final List<double> _cellOffsets;
  final _basicInfoController = StreamController<JbdBasicInfo>.broadcast();
  final _cellVoltagesController = StreamController<List<double>>.broadcast();

  Timer? _timer;
  bool _disposed = false;

  double _soc = 63;
  bool _charging = false;
  bool _chargeFetOn = true;
  bool _dischargeFetOn = true;
  int _cycleCount = 12;
  double _time = 0;

  @override
  Stream<JbdBasicInfo> get basicInfo => _basicInfoController.stream;

  @override
  Stream<List<double>> get cellVoltages => _cellVoltagesController.stream;

  @override
  String get remoteId => 'demo';

  @override
  String? get hardwareVersion => 'JBD-DEMO10S-001';

  @override
  Future<void> setMosfets({
    required bool chargeOn,
    required bool dischargeOn,
  }) async {
    if (_disposed) {
      throw StateError('BMS session is closed');
    }
    // Mimic real command latency, then confirm via the next emission just
    // like hardware does.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _chargeFetOn = chargeOn;
    _dischargeFetOn = dischargeOn;
    _tick();
  }

  @override
  Future<void> disconnect() => dispose();

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _timer?.cancel();
    await _basicInfoController.close();
    await _cellVoltagesController.close();
  }

  void _tick() {
    if (_disposed) {
      return;
    }
    _time += _tickInterval.inMilliseconds / 1000;

    // Swing between charge and discharge at the SOC extremes.
    if (_soc <= 25) {
      _charging = true;
    } else if (_soc >= 96) {
      _charging = false;
      _cycleCount++;
    }

    final fetAllows = _charging ? _chargeFetOn : _dischargeFetOn;
    double current;
    if (!fetAllows) {
      current = 0;
    } else if (_charging) {
      current = 5.2 + sin(_time / 23) * 0.8 + _noise(0.15);
    } else {
      current = -3.6 + sin(_time / 31) * 1.4 + _noise(0.2);
    }

    // 24 Ah pack: convert amps over the tick into SOC movement, sped up so
    // trends show within a demo session.
    const demoTimeFactor = 60.0;
    _soc += current *
        _tickInterval.inMilliseconds /
        1000 *
        demoTimeFactor /
        3600 /
        _nominalAh *
        100;
    _soc = _soc.clamp(0, 100);

    // Cell voltage follows SOC (rough Li-ion curve), plus persistent offsets
    // and jitter.
    final base = 3.10 + (_soc / 100) * 1.02;
    final cells = [
      for (var i = 0; i < _cellCount; i++)
        base + _cellOffsets[i] + _noise(0.0015),
    ];
    final packVoltage = cells.reduce((a, b) => a + b);

    // Balance the two highest cells while charging above 80%.
    var balanceStatus = 0;
    if (_charging && _soc > 80) {
      final sorted = List.generate(_cellCount, (i) => i)
        ..sort((a, b) => cells[b].compareTo(cells[a]));
      balanceStatus = (1 << sorted[0]) | (1 << sorted[1]);
    }

    var protectionStatus = 0;
    if (!_chargeFetOn || !_dischargeFetOn) {
      protectionStatus |= JbdBasicInfo.softwareLockBit;
    }

    final info = JbdBasicInfo(
      totalVoltage: packVoltage,
      current: current,
      remainingCapacityAh: _nominalAh * _soc / 100,
      nominalCapacityAh: _nominalAh,
      cycleCount: _cycleCount,
      protectionStatus: protectionStatus,
      socPercent: _soc.round(),
      chargeFetOn: _chargeFetOn,
      dischargeFetOn: _dischargeFetOn,
      cellCount: _cellCount,
      temperaturesCelsius: [
        21.5 + sin(_time / 60) * 2 + _noise(0.1),
        23.0 + sin(_time / 45) * 1.5 + _noise(0.1),
      ],
      balanceStatus: balanceStatus,
      softwareVersion: 0x25,
      // 2024-03-01: (24 << 9) | (3 << 5) | 1
      productionDateRaw: (24 << 9) | (3 << 5) | 1,
    );

    if (!_basicInfoController.isClosed) {
      _basicInfoController.add(info);
    }
    if (!_cellVoltagesController.isClosed) {
      _cellVoltagesController.add(cells);
    }
  }

  double _noise(double amplitude) =>
      (_random.nextDouble() * 2 - 1) * amplitude;
}
