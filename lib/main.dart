import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'jbd_bms.dart';

final bluetoothScannerClientProvider = Provider<BluetoothScannerClient>(
  (_) => FlutterBlueScannerClient(),
);

void main() {
  runApp(const ProviderScope(child: BmsApp()));
}

class BmsApp extends StatelessWidget {
  const BmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JBD BMS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F7A5A)),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final List<BmsScanDevice> _devices = [];
  final _permissions = BluetoothPermissionService();
  late final BluetoothScannerClient _bluetooth;

  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  StreamSubscription<List<BmsScanDevice>>? _scanResultsSubscription;
  StreamSubscription<bool>? _isScanningSubscription;

  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  bool _isBluetoothSupported = true;
  bool _isConnecting = false;
  bool _isScanning = false;
  DeviceConnectionSummary? _connectionSummary;
  JbdBmsSession? _session;
  JbdBasicInfo? _telemetry;
  bool? _pendingMosfetToggle;
  bool _showAllDevices = false;
  StreamSubscription<JbdBasicInfo>? _telemetrySubscription;
  String _status = 'Ready to scan';

  @override
  void initState() {
    super.initState();
    _bluetooth = ref.read(bluetoothScannerClientProvider);
    _initBluetooth();
  }

  Future<void> _initBluetooth() async {
    final isSupported = await _bluetooth.isSupported;
    if (!mounted) {
      return;
    }

    setState(() {
      _isBluetoothSupported = isSupported;
      if (!isSupported) {
        _status = 'Bluetooth LE is not supported on this device';
      }
    });

    if (!isSupported) {
      return;
    }

    _adapterStateSubscription = _bluetooth.adapterState.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() {
        _adapterState = state;
        if (state != BluetoothAdapterState.on) {
          _status = 'Bluetooth is ${state.label}';
        }
      });
    });

    _scanResultsSubscription = _bluetooth.scanResults.listen(
      (devices) {
        if (!mounted) {
          return;
        }
        setState(() {
          _devices
            ..clear()
            ..addAll(devices);
          _devices.sort(BmsScanDevice.compareForDisplay);
        });
      },
      onError: (Object error) {
        if (!mounted) {
          return;
        }
        setState(() {
          _status = 'Scan failed: $error';
        });
      },
    );

    _isScanningSubscription = _bluetooth.isScanning.listen((isScanning) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isScanning = isScanning;
        if (!isScanning && _status == 'Scanning for BLE devices') {
          _status = _devices.isEmpty
              ? 'No BLE devices found'
              : 'Found ${_devices.length} BLE device(s)';
        }
      });
    });
  }

  @override
  void dispose() {
    _adapterStateSubscription?.cancel();
    _scanResultsSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _telemetrySubscription?.cancel();
    final session = _session;
    if (session != null) {
      unawaited(session.disconnect());
    }
    if (_bluetooth.isScanningNow) {
      unawaited(_bluetooth.stopScan());
    }
    super.dispose();
  }

  Future<void> _startScan() async {
    if (!_isBluetoothSupported) {
      return;
    }

    setState(() {
      _status = 'Checking Bluetooth permissions';
    });

    final permissionResult = await _permissions.requestRequiredPermissions();
    if (!mounted) {
      return;
    }
    if (!permissionResult.isGranted) {
      setState(() {
        _status = permissionResult.message;
      });
      return;
    }

    if (_adapterState != BluetoothAdapterState.on) {
      setState(() {
        _status = 'Turn Bluetooth on before scanning';
      });
      return;
    }

    setState(() {
      _devices.clear();
      _status = 'Scanning for BLE devices';
    });

    try {
      await _bluetooth.startScan(
        androidUsesFineLocation: permissionResult.usesFineLocation,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Could not start scan: $error';
      });
    }
  }

  Future<void> _stopScan() async {
    await _bluetooth.stopScan();
  }

  Future<void> _connectToDevice(BmsScanDevice device) async {
    if (_isConnecting) {
      return;
    }

    setState(() {
      _isConnecting = true;
      _connectionSummary = null;
      _status = 'Connecting to ${device.name}';
    });

    try {
      if (_isScanning) {
        await _bluetooth.stopScan();
      }
      await _teardownSession();
      final connection = await _bluetooth.connectAndDiscover(device);
      final session = connection.session;
      if (!mounted) {
        await session?.disconnect();
        return;
      }
      setState(() {
        _connectionSummary = connection.summary;
        _session = session;
        _telemetry = null;
        _pendingMosfetToggle = null;
        _status = session == null
            ? 'Connected to ${connection.summary.name}, '
                'but it has no JBD BMS service'
            : 'Connected to ${connection.summary.name}';
      });
      _telemetrySubscription = session?.basicInfo.listen(
        (info) {
          if (!mounted) {
            return;
          }
          setState(() {
            _telemetry = info;
          });
        },
        onDone: () {
          if (!mounted || !identical(_session, session)) {
            return;
          }
          setState(() {
            _session = null;
            _telemetry = null;
            _pendingMosfetToggle = null;
            _connectionSummary = null;
            _status = 'Device disconnected';
          });
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Connection failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  Future<void> _teardownSession() async {
    final session = _session;
    _session = null;
    await _telemetrySubscription?.cancel();
    _telemetrySubscription = null;
    await session?.disconnect();
  }

  Future<void> _disconnect() async {
    await _teardownSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _connectionSummary = null;
      _telemetry = null;
      _pendingMosfetToggle = null;
      _status = 'Disconnected';
    });
  }

  Future<void> _setMosfets(bool enabled) async {
    final session = _session;
    if (session == null || _pendingMosfetToggle != null) {
      return;
    }
    setState(() {
      _pendingMosfetToggle = enabled;
      _status = enabled
          ? 'Turning charge & discharge MOSFETs on'
          : 'Turning charge & discharge MOSFETs off';
    });
    try {
      await session.setMosfets(chargeOn: enabled, dischargeOn: enabled);
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingMosfetToggle = null;
        _status = enabled
            ? 'Charge & discharge MOSFETs are on'
            : 'Charge & discharge MOSFETs are off';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingMosfetToggle = null;
        _status = 'MOSFET command failed: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('JBD BMS'),
        actions: [
          if (_session == null)
            IconButton(
              tooltip: 'Refresh scan',
              onPressed: _isScanning ? null : _startScan,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusPanel(
                adapterState: _adapterState,
                connectionSummary: _connectionSummary,
                isConnecting: _isConnecting,
                isScanning: _isScanning,
                status: _status,
                colorScheme: colorScheme,
              ),
              const SizedBox(height: 16),
              if (_session != null)
                _BmsPanel(
                  telemetry: _telemetry,
                  mosfetsOn:
                      _pendingMosfetToggle ?? _telemetry?.mosfetsOn ?? false,
                  isTogglePending: _pendingMosfetToggle != null,
                  onMosfetsChanged: _setMosfets,
                  onDisconnect: _disconnect,
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isScanning ? null : _startScan,
                        icon: const Icon(Icons.bluetooth_searching),
                        label: const Text('Scan'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      tooltip: 'Stop scan',
                      onPressed: _isScanning ? _stopScan : null,
                      icon: const Icon(Icons.stop),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Show all devices'),
                  value: _showAllDevices,
                  onChanged: (value) {
                    setState(() {
                      _showAllDevices = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _DeviceList(
                    devices: _showAllDevices
                        ? _devices
                        : _devices
                            .where((device) => device.isLikelyBms)
                            .toList(),
                    hiddenDeviceCount: _showAllDevices
                        ? 0
                        : _devices
                            .where((device) => !device.isLikelyBms)
                            .length,
                    isConnecting: _isConnecting,
                    isScanning: _isScanning,
                    onDeviceSelected: _connectToDevice,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.adapterState,
    required this.connectionSummary,
    required this.isConnecting,
    required this.isScanning,
    required this.status,
    required this.colorScheme,
  });

  final BluetoothAdapterState adapterState;
  final DeviceConnectionSummary? connectionSummary;
  final bool isConnecting;
  final bool isScanning;
  final String status;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isConnecting
                      ? Icons.bluetooth_connected
                      : isScanning
                          ? Icons.radar
                          : Icons.bluetooth,
                  color: isConnecting || isScanning
                      ? colorScheme.primary
                      : colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Text(
                  isConnecting
                      ? 'Connecting'
                      : connectionSummary == null
                          ? isScanning
                              ? 'Scanning'
                              : 'Disconnected'
                          : 'Connected',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Bluetooth: ${adapterState.label}'),
            Text('Status: $status'),
            if (connectionSummary != null) ...[
              const SizedBox(height: 8),
              Text('Device: ${connectionSummary!.name}'),
              Text('Services: ${connectionSummary!.serviceCount}'),
              Text('Characteristics: ${connectionSummary!.characteristicCount}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _BmsPanel extends StatelessWidget {
  const _BmsPanel({
    required this.telemetry,
    required this.mosfetsOn,
    required this.isTogglePending,
    required this.onMosfetsChanged,
    required this.onDisconnect,
  });

  final JbdBasicInfo? telemetry;
  final bool mosfetsOn;
  final bool isTogglePending;
  final ValueChanged<bool> onMosfetsChanged;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final telemetry = this.telemetry;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Battery', style: theme.textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: onDisconnect,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                ),
              ],
            ),
            if (telemetry == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Waiting for battery data...'),
              )
            else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${telemetry.socPercent}%',
                    style: theme.textTheme.displaySmall,
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'state of charge',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: telemetry.socPercent.clamp(0, 100) / 100,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 12),
              Text(
                '${telemetry.totalVoltage.toStringAsFixed(2)} V   '
                '${telemetry.current.toStringAsFixed(2)} A',
              ),
              Text(
                '${telemetry.remainingCapacityAh.toStringAsFixed(1)} / '
                '${telemetry.nominalCapacityAh.toStringAsFixed(1)} Ah   '
                '${telemetry.cycleCount} cycles',
              ),
              if (telemetry.temperaturesCelsius.isNotEmpty)
                Text(
                  'Temperature: ${telemetry.temperaturesCelsius.map(
                        (t) => '${t.toStringAsFixed(1)} °C',
                      ).join(', ')}',
                ),
              if (telemetry.hasProtectionFault)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Protection active (status 0x'
                    '${telemetry.protectionStatus.toRadixString(16)})',
                    style: TextStyle(color: colorScheme.error),
                  ),
                ),
            ],
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Charge & discharge MOSFETs'),
              subtitle: Text(
                telemetry == null
                    ? 'Waiting for FET status'
                    : 'Charge FET ${telemetry.chargeFetOn ? 'on' : 'off'}, '
                        'discharge FET '
                        '${telemetry.dischargeFetOn ? 'on' : 'off'}',
              ),
              value: mosfetsOn,
              onChanged: telemetry == null || isTogglePending
                  ? null
                  : onMosfetsChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({
    required this.devices,
    required this.hiddenDeviceCount,
    required this.isConnecting,
    required this.isScanning,
    required this.onDeviceSelected,
  });

  final List<BmsScanDevice> devices;
  final int hiddenDeviceCount;
  final bool isConnecting;
  final bool isScanning;
  final ValueChanged<BmsScanDevice> onDeviceSelected;

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      final String message;
      if (hiddenDeviceCount > 0) {
        message = 'No likely BMS found, but $hiddenDeviceCount other BLE '
            'device(s) are hidden. Turn on "Show all devices" to list them.';
      } else if (isScanning) {
        message = 'Listening for BLE advertisements...';
      } else {
        message = 'No devices yet. Start a scan with the BMS powered on.';
      }
      return Center(
        child: Text(message, textAlign: TextAlign.center),
      );
    }

    return ListView.separated(
      itemCount: devices.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final device = devices[index];
        return ListTile(
          leading: Icon(
            device.isLikelyBms ? Icons.battery_charging_full : Icons.bluetooth,
          ),
          title: Text(device.name),
          subtitle: Text(device.remoteId),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${device.rssi} dBm'),
              if (device.isLikelyBms)
                Text(
                  'likely BMS',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
          enabled: !isConnecting,
          onTap: () => onDeviceSelected(device),
        );
      },
    );
  }
}

@immutable
class BmsScanDevice {
  const BmsScanDevice({
    required this.name,
    required this.remoteId,
    required this.rssi,
    required this.isLikelyBms,
  });

  factory BmsScanDevice.fromScanResult(ScanResult result) {
    final advertisedName = result.advertisementData.advName.trim();
    final platformName = result.device.platformName.trim();
    final name = advertisedName.isNotEmpty
        ? advertisedName
        : platformName.isNotEmpty
            ? platformName
            : 'Unnamed BLE device';
    final lowerName = name.toLowerCase();

    return BmsScanDevice(
      name: name,
      remoteId: result.device.remoteId.str,
      rssi: result.rssi,
      isLikelyBms: lowerName.contains('jbd') ||
          lowerName.contains('xiaoxiang') ||
          lowerName.contains('bms') ||
          lowerName.contains('sp17'),
    );
  }

  final String name;
  final String remoteId;
  final int rssi;
  final bool isLikelyBms;

  static int compareForDisplay(BmsScanDevice a, BmsScanDevice b) {
    if (a.isLikelyBms != b.isLikelyBms) {
      return a.isLikelyBms ? -1 : 1;
    }
    return b.rssi.compareTo(a.rssi);
  }
}

class BluetoothPermissionService {
  Future<BluetoothPermissionResult> requestRequiredPermissions() async {
    if (kIsWeb || !Platform.isAndroid) {
      return const BluetoothPermissionResult.granted(usesFineLocation: false);
    }

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    if (sdkInt >= 31) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();

      final granted = statuses.values.every((status) => status.isGranted);
      return BluetoothPermissionResult(
        isGranted: granted,
        usesFineLocation: false,
        message: granted
            ? 'Bluetooth permissions granted'
            : 'Bluetooth scan/connect permission is required',
      );
    }

    final status = await Permission.locationWhenInUse.request();
    return BluetoothPermissionResult(
      isGranted: status.isGranted,
      usesFineLocation: true,
      message: status.isGranted
          ? 'Location permission granted for BLE scanning'
          : 'Location permission is required for BLE scanning on this Android version',
    );
  }
}

abstract class BluetoothScannerClient {
  Future<bool> get isSupported;

  Stream<BluetoothAdapterState> get adapterState;

  Stream<List<BmsScanDevice>> get scanResults;

  Stream<bool> get isScanning;

  bool get isScanningNow;

  Future<void> startScan({required bool androidUsesFineLocation});

  Future<void> stopScan();

  Future<BmsConnection> connectAndDiscover(BmsScanDevice device);
}

class FlutterBlueScannerClient implements BluetoothScannerClient {
  @override
  Future<bool> get isSupported => FlutterBluePlus.isSupported;

  @override
  Stream<BluetoothAdapterState> get adapterState => FlutterBluePlus.adapterState;

  @override
  Stream<List<BmsScanDevice>> get scanResults => FlutterBluePlus.scanResults.map(
        (results) => results.map(BmsScanDevice.fromScanResult).toList(),
      );

  @override
  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  @override
  bool get isScanningNow => FlutterBluePlus.isScanningNow;

  @override
  Future<void> startScan({required bool androidUsesFineLocation}) {
    return FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      removeIfGone: const Duration(seconds: 5),
      continuousUpdates: true,
      androidUsesFineLocation: androidUsesFineLocation,
    );
  }

  @override
  Future<void> stopScan() {
    return FlutterBluePlus.stopScan();
  }

  @override
  Future<BmsConnection> connectAndDiscover(BmsScanDevice device) async {
    final bluetoothDevice = BluetoothDevice.fromId(device.remoteId);
    await bluetoothDevice.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 15),
    );
    try {
      final services = await bluetoothDevice.discoverServices(timeout: 15);
      final session = await JbdBmsSession.start(bluetoothDevice, services);
      return BmsConnection(
        summary: DeviceConnectionSummary(
          name: device.name,
          remoteId: device.remoteId,
          serviceCount: services.length,
          characteristicCount: services.fold<int>(
            0,
            (count, service) => count + service.characteristics.length,
          ),
        ),
        session: session,
      );
    } catch (_) {
      unawaited(bluetoothDevice.disconnect());
      rethrow;
    }
  }
}

/// Result of connecting to a device: GATT stats plus a live JBD session when
/// the device speaks the JBD protocol.
@immutable
class BmsConnection {
  const BmsConnection({required this.summary, required this.session});

  final DeviceConnectionSummary summary;
  final JbdBmsSession? session;
}

@immutable
class DeviceConnectionSummary {
  const DeviceConnectionSummary({
    required this.name,
    required this.remoteId,
    required this.serviceCount,
    required this.characteristicCount,
  });

  final String name;
  final String remoteId;
  final int serviceCount;
  final int characteristicCount;
}

@immutable
class BluetoothPermissionResult {
  const BluetoothPermissionResult({
    required this.isGranted,
    required this.usesFineLocation,
    required this.message,
  });

  const BluetoothPermissionResult.granted({required this.usesFineLocation})
      : isGranted = true,
        message = 'Permissions granted';

  final bool isGranted;
  final bool usesFineLocation;
  final String message;
}

extension on BluetoothAdapterState {
  String get label {
    switch (this) {
      case BluetoothAdapterState.on:
        return 'on';
      case BluetoothAdapterState.off:
        return 'off';
      case BluetoothAdapterState.turningOn:
        return 'turning on';
      case BluetoothAdapterState.turningOff:
        return 'turning off';
      case BluetoothAdapterState.unauthorized:
        return 'unauthorized';
      case BluetoothAdapterState.unavailable:
        return 'unavailable';
      case BluetoothAdapterState.unknown:
        return 'unknown';
    }
  }
}
