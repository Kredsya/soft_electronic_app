import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:async';
import 'dart:convert';
import 'report_screen.dart';

class MeasurementScreenFixed extends StatefulWidget {
  const MeasurementScreenFixed({super.key});

  @override
  State<MeasurementScreenFixed> createState() => _MeasurementScreenFixedState();
}

class _MeasurementScreenFixedState extends State<MeasurementScreenFixed>
    with TickerProviderStateMixin {
  // 블루투스 관련 변수 - 두 개의 HC-06 모듈 지원
  List<BluetoothDevice> _devicesList = [];
  BluetoothDevice? _imuDevice;
  BluetoothDevice? _fsrDevice;
  StreamSubscription<List<int>>? _imuSubscription;
  StreamSubscription<List<int>>? _fsrSubscription;
  bool _isScanning = false;
  bool _isConnecting = false;
  String _currentPosture = '연결 대기 중';
  String _rawData = '';
  double _confidence = 0.0;

  // 소켓 관련 변수
  WebSocketChannel? _webSocket;
  bool _isSocketConnected = false;
  String _serverPosture = '서버 연결 대기 중';

  // 새로운 모듈 상태 관리 변수
  bool _imuConnected = false;
  bool _fsrConnected = false;
  String _imuStatus = 'disconnected'; // disconnected, connected, ready
  String _fsrStatus = 'disconnected'; // disconnected, connected, ready
  bool _modulesReady = false;

  // 측정 관련 변수
  bool _isMeasuring = false;
  bool _isCalibrating = false;
  int _calibrationCountdown = 5;
  double? _baselinePitch;
  List<Map<String, dynamic>> _measurementData = [];
  Timer? _calibrationTimer;
  Timer? _measurementTimer;

  // 슬라이딩 윈도우 데이터 처리 변수
  List<Map<String, dynamic>> _imuBuffer = [];
  List<Map<String, dynamic>> _fsrBuffer = [];
  List<Map<String, dynamic>> _windowData = [];
  Timer? _dataWindowTimer;
  int _dataId = 1;

  // 애니메이션 관련 변수
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _rotationController;

  // 연결 상태 확인 헬퍼 함수
  bool get _isConnected => _imuDevice != null || _fsrDevice != null;

  // 연결 상태 텍스트 반환 함수
  String _getConnectionStatusText() {
    if (_imuDevice != null && _fsrDevice != null) {
      return '두 모듈 모두 연결됨 - 측정 준비 완료';
    } else if (_imuDevice != null) {
      return 'IMU 연결됨 - FSR 모듈을 추가로 연결하세요';
    } else if (_fsrDevice != null) {
      return 'FSR 연결됨 - IMU 모듈을 추가로 연결하세요';
    } else {
      return '주변의 블루투스 장치를 찾아보세요';
    }
  }

  // 다음 연결할 모듈 정보 반환 함수
  String _getNextConnectionInfo() {
    if (_imuDevice == null && _fsrDevice == null) {
      return '첫 번째 장치를 IMU 모듈로 연결합니다';
    } else if (_imuDevice != null && _fsrDevice == null) {
      return '다음 장치를 FSR 모듈로 연결합니다';
    } else if (_imuDevice == null && _fsrDevice != null) {
      return '다음 장치를 IMU 모듈로 연결합니다';
    } else {
      return '모든 모듈이 연결되었습니다';
    }
  }

  // 장치 연결 상태 반환 함수
  String _getDeviceConnectionStatus(BluetoothDevice device) {
    if (_imuDevice?.remoteId.str == device.remoteId.str) {
      return 'IMU 연결됨';
    } else if (_fsrDevice?.remoteId.str == device.remoteId.str) {
      return 'FSR 연결됨';
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _requestPermissions();
    _checkBluetoothState();
    // 서버와 먼저 연결
    _connectToServer();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _rotationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    _pulseController.repeat(reverse: true);
    _rotationController.repeat();
  }

  // 블루투스 상태 확인 함수
  Future<void> _checkBluetoothState() async {
    try {
      BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
      print('블루투스 상태: $state');

      if (state != BluetoothAdapterState.on) {
        setState(() {
          _currentPosture = '블루투스를 켜주세요';
        });
        return;
      }

      // 위치 서비스 확인
      bool locationEnabled = await Permission.location.serviceStatus.isEnabled;
      print('위치 서비스 상태: $locationEnabled');

      if (!locationEnabled) {
        setState(() {
          _currentPosture = '위치 서비스를 켜주세요 (블루투스 스캔에 필요)';
        });
        return;
      }
    } catch (e) {
      print('블루투스 상태 확인 오류: $e');
    }
  }

  // 권한 요청
  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses =
        await [
          Permission.bluetooth,
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.location,
          Permission.locationWhenInUse,
        ].request();

    print('권한 상태: $statuses');
  }

  // 블루투스 스캔 시작
  Future<void> _startScan() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _devicesList.clear();
      _currentPosture = '주변 장치 스캔 중...';
    });

    try {
      // 기존 스캔 중지
      await FlutterBluePlus.stopScan();

      print('📡 블루투스 스캔 시작...');

      var subscription = FlutterBluePlus.scanResults.listen(
        (results) {
          print('스캔 결과: ${results.length}개 장치 발견');

          Set<String> deviceIds = {};
          List<BluetoothDevice> uniqueDevices = [];

          for (var result in results) {
            BluetoothDevice device = result.device;
            String deviceId = device.remoteId.str;

            // 중복 제거
            if (!deviceIds.contains(deviceId)) {
              deviceIds.add(deviceId);
              uniqueDevices.add(device);

              String deviceName =
                  device.platformName.isNotEmpty
                      ? device.platformName
                      : '이름 없음';
              print('발견된 장치: $deviceName ($deviceId) - RSSI: ${result.rssi}');
            }
          }

          if (mounted) {
            setState(() {
              _devicesList = uniqueDevices;
            });
          }
        },
        onError: (e) {
          print('❌ 스캔 오류: $e');
          setState(() {
            _isScanning = false;
            _currentPosture = '스캔 오류: $e';
          });
        },
      );

      // 스캔 시작
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
        withServices: [],
        withNames: [],
        androidUsesFineLocation: true,
      );

      // 스캔 완료 후 정리
      await Future.delayed(Duration(seconds: 9)); // 타임아웃 + 1초
      await subscription.cancel();
      await FlutterBluePlus.stopScan(); // 확실히 스캔 중지

      setState(() {
        _isScanning = false;
        if (_devicesList.isEmpty) {
          _currentPosture = '주변에서 블루투스 장치를 찾을 수 없습니다';
        } else {
          _currentPosture =
              '${_devicesList.length}개의 장치를 발견했습니다. 연결할 장치를 선택하세요.';
        }
      });
    } catch (e) {
      print('❌ 블루투스 스캔 오류: $e');
      setState(() {
        _isScanning = false;
        _currentPosture = '스캔 오류: $e';
      });
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _currentPosture =
          '${device.platformName.isNotEmpty ? device.platformName : device.remoteId.str}에 연결 중...';
    });

    try {
      // 빈 슬롯 찾기 (IMU 또는 FSR)
      bool connectAsIMU = (_imuDevice == null);
      bool connectAsFSR = (_fsrDevice == null && !connectAsIMU);

      if (!connectAsIMU && !connectAsFSR) {
        setState(() {
          _isConnecting = false;
          _currentPosture = '이미 두 모듈이 모두 연결되어 있습니다. 기존 연결을 해제하고 다시 시도하세요.';
        });
        return;
      }

      String moduleType = connectAsIMU ? "IMU" : "FSR";
      print(
        '📞 $moduleType 모듈로 장치 연결 시도: ${device.platformName} (${device.remoteId})',
      );
      print('📞 장치 연결 시도: ${device.platformName} (${device.remoteId})');
      await device.connect(timeout: Duration(seconds: 10));
      print('✅ 기기에 연결됨: ${device.platformName}');

      // 연결 상태 확인
      var connectionState = await device.connectionState.first;
      print('📱 연결 상태: $connectionState');

      if (connectionState != BluetoothConnectionState.connected) {
        throw Exception('연결 실패: 상태가 connected가 아님');
      }

      print('🔍 서비스 탐색 시작...');
      List<BluetoothService> services = await device.discoverServices();
      print('📋 서비스 개수: ${services.length}');

      bool characteristicFound = false;

      // 통신 채널 설정
      for (BluetoothService service in services) {
        print('🔧 서비스 UUID: ${service.uuid}');

        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          print('📊 특성 UUID: ${characteristic.uuid}');
          print(
            '📋 특성 속성: notify=${characteristic.properties.notify}, '
            'read=${characteristic.properties.read}, '
            'write=${characteristic.properties.write}, '
            'writeWithoutResponse=${characteristic.properties.writeWithoutResponse}',
          );

          // 데이터 수신용 특성 (notify 가능한 특성)
          if (characteristic.properties.notify) {
            try {
              print('📡 알림 설정 중...');
              await characteristic.setNotifyValue(true);

              if (connectAsIMU) {
                _imuSubscription?.cancel();
                _imuSubscription = characteristic.value.listen(
                  (value) {
                    print('📥 IMU 데이터 수신: ${value.length}바이트');
                    _handleBluetoothData(value, 'IMU');
                  },
                  onError: (error) {
                    print('❌ IMU 데이터 수신 오류: $error');
                  },
                );
              } else if (connectAsFSR) {
                _fsrSubscription?.cancel();
                _fsrSubscription = characteristic.value.listen(
                  (value) {
                    print('📥 FSR 데이터 수신: ${value.length}바이트');
                    _handleBluetoothData(value, 'FSR');
                  },
                  onError: (error) {
                    print('❌ FSR 데이터 수신 오류: $error');
                  },
                );
              }

              print('✅ 데이터 수신 채널 설정됨: ${characteristic.uuid}');
              characteristicFound = true;
            } catch (e) {
              print('❌ 알림 설정 오류: $e');
            }
          }
        }
      }

      if (!characteristicFound) {
        throw Exception('데이터 수신용 특성을 찾을 수 없습니다');
      }

      setState(() {
        if (connectAsIMU) {
          _imuDevice = device;
        } else if (connectAsFSR) {
          _fsrDevice = device;
        }
        _isConnecting = false;
        String deviceName =
            device.platformName.isNotEmpty
                ? device.platformName
                : device.remoteId.str;
        _currentPosture =
            '$deviceName에 연결됨 (${connectAsIMU ? "IMU" : "FSR"}) - 모듈 응답 대기 중';
      });

      print('✅ 블루투스 연결 및 설정 완료 - 모듈 ready 메시지 대기 중');

      // Ready 명령 전송 제거 - 모듈에서 자동으로 ready 상태를 전송함

      // FSR 모듈에 추가 명령 전송 (FSR 데이터 요청)
      if (connectAsFSR) {
        print('📤 FSR 모듈에 데이터 전송 요청...');
        await Future.delayed(Duration(seconds: 1)); // 연결 안정화 대기
        await _sendCommandToDevice(device, '{"command": "request_fsr_data"}');
      }
    } catch (e) {
      print('❌ 연결 오류 상세: $e');

      // 연결 실패 시 정리
      try {
        await device.disconnect();
      } catch (disconnectError) {
        print('⚠️ 연결 해제 중 오류: $disconnectError');
      }

      setState(() {
        _isConnecting = false;
        _currentPosture = '연결 실패: ${e.toString()}';
      });
    }
  }

  void _handleBluetoothData(List<int> data, [String? deviceType]) {
    String dataString = String.fromCharCodes(data).trim();
    print(
      '📡 수신 데이터 원본 (${deviceType ?? "unknown"}): "$dataString" (길이: ${dataString.length})',
    );

    // 디버깅을 위한 추가 정보
    print('🔍 연결된 장치 정보:');
    print(
      '   - IMU 장치: ${_imuDevice?.platformName ?? "연결안됨"} (${_imuDevice?.remoteId.str ?? "N/A"})',
    );
    print(
      '   - FSR 장치: ${_fsrDevice?.platformName ?? "연결안됨"} (${_fsrDevice?.remoteId.str ?? "N/A"})',
    );
    print('   - 데이터 수신 장치 타입: $deviceType');

    if (mounted) {
      setState(() {
        _rawData = dataString;
      });
    }

    // 빈 데이터나 너무 짧은 데이터 체크 (최소 길이를 2로 낮춤)
    if (dataString.isEmpty || dataString.length < 2) {
      print('⚠️ 빈 데이터 또는 너무 짧은 데이터');
      return;
    }

    // JSON이 아닌 일반 텍스트도 처리
    if (!dataString.startsWith('{')) {
      print('📝 일반 텍스트 메시지: $dataString');

      // 간단한 텍스트 기반 응답 처리
      if (dataString.toUpperCase().contains('IMU') &&
          dataString.toUpperCase().contains('READY')) {
        _handleModuleStatusResponse({'module': 'IMU', 'status': 'ready'});
        return;
      }
      if (dataString.toUpperCase().contains('FSR') &&
          dataString.toUpperCase().contains('READY')) {
        _handleModuleStatusResponse({'module': 'FSR', 'status': 'ready'});
        return;
      }

      // 기타 상태 메시지 처리
      if (mounted) {
        setState(() {
          _currentPosture = dataString;
        });
      }
      return;
    }

    try {
      Map<String, dynamic> jsonData = jsonDecode(dataString);
      print('✅ JSON 파싱 성공: $jsonData');

      // 모듈 상태 응답 처리
      if (jsonData.containsKey('module') && jsonData.containsKey('status')) {
        _handleModuleStatusResponse(jsonData);
      }
      // 측정 데이터 처리
      else if (jsonData.containsKey('module') &&
          jsonData.containsKey('value')) {
        _handleMeasurementData(jsonData);
      }
      // 일반 상태 메시지 처리
      else if (jsonData.containsKey('status')) {
        _handleStatusMessage(jsonData);
      }
    } catch (e) {
      print('❌ JSON 파싱 오류: $e');
      print('📝 JSON이 아닌 원본 메시지로 처리: $dataString');

      // JSON 파싱 실패 시 원본 메시지를 상태로 표시
      if (mounted) {
        setState(() {
          _currentPosture = dataString;
        });
      }
    }
  }

  void _handleModuleStatusResponse(Map<String, dynamic> data) {
    String module = data['module'] ?? '';
    String status = data['status'] ?? '';

    print('📡 모듈 상태 응답: $module - $status');

    if (mounted) {
      setState(() {
        if (module.toUpperCase() == 'IMU') {
          _imuConnected = true;
          _imuStatus = status;
        } else if (module.toUpperCase() == 'FSR') {
          _fsrConnected = true;
          _fsrStatus = status;
        }

        // 두 모듈 모두 ready인지 확인
        _modulesReady = (_imuStatus == 'ready' && _fsrStatus == 'ready');

        if (_modulesReady) {
          _currentPosture = '모든 모듈 준비 완료 - 측정 시작 가능';
        } else {
          _currentPosture = '모듈 준비 중... (IMU: $_imuStatus, FSR: $_fsrStatus)';
        }
      });
    }
  }

  void _handleMeasurementData(Map<String, dynamic> data) {
    String module = data['module'] ?? '';
    List<dynamic> value = data['value'] ?? [];
    int timestamp = data['timestamp'] ?? 0;

    print('📊 측정 데이터 수신: $module - timestamp: $timestamp');
    print(
      '📊 현재 IMU 버퍼 크기: ${_imuBuffer.length}, FSR 버퍼 크기: ${_fsrBuffer.length}',
    );

    Map<String, dynamic> dataPoint = {
      'module': module,
      'value': value,
      'timestamp': timestamp,
      'received_at': DateTime.now().millisecondsSinceEpoch,
    };

    // 모듈별로 버퍼에 저장
    if (module.toUpperCase() == 'IMU') {
      _imuBuffer.add(dataPoint);
      if (_imuBuffer.length > 10) _imuBuffer.removeAt(0);
      print('✅ IMU 데이터 버퍼에 저장됨 - 현재 ${_imuBuffer.length}개');
    } else if (module.toUpperCase() == 'FSR') {
      _fsrBuffer.add(dataPoint);
      if (_fsrBuffer.length > 10) _fsrBuffer.removeAt(0);
      print('✅ FSR 데이터 버퍼에 저장됨 - 현재 ${_fsrBuffer.length}개');
    } else {
      print('⚠️ 알 수 없는 모듈 타입: $module');
    }

    _processDataWindow();
  }

  void _processDataWindow() {
    print(
      '🔍 데이터 윈도우 처리 시작 - IMU: ${_imuBuffer.length}개, FSR: ${_fsrBuffer.length}개',
    );

    if (_imuBuffer.length >= 3 && _fsrBuffer.length >= 3) {
      List<Map<String, dynamic>> recentIMU = _imuBuffer.take(3).toList();
      List<Map<String, dynamic>> recentFSR = _fsrBuffer.take(3).toList();

      List<double> avgIMU = _calculateAverageIMU(recentIMU);
      List<double> avgFSR = _calculateAverageFSR(recentFSR);

      Map<String, dynamic> serverData = {
        'id': _dataId++,
        'device_id':
            '${_imuDevice?.remoteId.str ?? "unknown"}_${_fsrDevice?.remoteId.str ?? "unknown"}',
        'IMU': avgIMU,
        'FSR': avgFSR,
      };

      if (_isSocketConnected) {
        _sendDataToServer(serverData);
      }

      print('📤 서버 전송 데이터: $serverData');
    } else {
      print(
        '⏳ 데이터 부족 - IMU: ${_imuBuffer.length}/3, FSR: ${_fsrBuffer.length}/3 (전송 대기)',
      );
    }
  }

  List<double> _calculateAverageIMU(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return [];

    List<double> sum = List.filled(data[0]['value'].length, 0.0);

    for (var item in data) {
      List<dynamic> values = item['value'];
      for (int i = 0; i < values.length && i < sum.length; i++) {
        sum[i] += (values[i] as num).toDouble();
      }
    }

    return sum.map((s) => s / data.length).toList();
  }

  List<double> _calculateAverageFSR(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return [];

    List<double> sum = List.filled(data[0]['value'].length, 0.0);

    for (var item in data) {
      List<dynamic> values = item['value'];
      for (int i = 0; i < values.length && i < sum.length; i++) {
        sum[i] += (values[i] as num).toDouble();
      }
    }

    return sum.map((s) => s / data.length).toList();
  }

  void _handleStatusMessage(Map<String, dynamic> data) {
    String status = data['status'] ?? '';
    print('📝 상태 메시지: $status');

    if (mounted) {
      setState(() {
        if (status.contains('Calibration starting')) {
          _currentPosture = '기준 자세 설정 시작 (5초간 자세 유지)';
        } else if (status.contains('Calibration complete')) {
          _currentPosture = '기준 자세 설정 완료 - 측정 시작';
          _isCalibrating = false;
          _isMeasuring = true;
        } else if (status.contains('Ready')) {
          _currentPosture = '센서 준비 완료';
        } else if (status.contains('stopped')) {
          _currentPosture = '측정 중지됨';
          _isMeasuring = false;
        } else {
          _currentPosture = status;
        }
      });
    }
  }

  Future<void> _startMeasurement() async {
    if (!_isConnected) {
      print('블루투스가 연결되지 않았습니다.');
      return;
    }

    if (!_isSocketConnected) {
      print('서버가 연결되지 않았습니다.');
      return;
    }

    if (!_modulesReady) {
      print('모듈이 준비되지 않았습니다. IMU: $_imuStatus, FSR: $_fsrStatus');
      return;
    }

    await _sendCommand('{"command": "start"}');

    if (mounted) {
      setState(() {
        _isCalibrating = true;
        _calibrationCountdown = 5;
        _currentPosture = '기준 자세 설정 중... (5초간 자세 유지)';
        _measurementData.clear();
        _imuBuffer.clear();
        _fsrBuffer.clear();
        _windowData.clear();
      });
    }

    _calibrationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _calibrationCountdown--;
          if (_calibrationCountdown > 0) {
            _currentPosture = '기준 자세 설정 중... (${_calibrationCountdown}초 남음)';
          }
        });
      }

      if (_calibrationCountdown <= 0) {
        timer.cancel();
        _finishCalibration();
      }
    });
  }

  void _finishCalibration() {
    if (mounted) {
      setState(() {
        _isCalibrating = false;
        _isMeasuring = true;
        _currentPosture = '측정 중... 첫 번째 자세는 정자세 기준';
        _baselinePitch = 0.0;
      });
    }
    print('✅ 캘리브레이션 완료 - 측정 시작');
  }

  Future<void> _sendCommand(String command) async {
    List<Future<void>> commands = [];

    if (_imuDevice != null) {
      commands.add(_sendCommandToDevice(_imuDevice!, command));
    }
    if (_fsrDevice != null) {
      commands.add(_sendCommandToDevice(_fsrDevice!, command));
    }

    if (commands.isEmpty) {
      print('❌ 연결된 장치가 없습니다');
      return;
    }

    await Future.wait(commands);
  }

  Future<void> _sendCommandToDevice(
    BluetoothDevice device,
    String command,
  ) async {
    try {
      print('📤 ${device.platformName}에 명령 전송 시도: $command');

      List<BluetoothService> services = await device.discoverServices();
      BluetoothCharacteristic? writeCharacteristic;

      for (BluetoothService service in services) {
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          if (characteristic.properties.write ||
              characteristic.properties.writeWithoutResponse) {
            writeCharacteristic = characteristic;
            print('✅ 쓰기 특성 발견: ${characteristic.uuid}');
            break;
          }
        }
        if (writeCharacteristic != null) break;
      }

      if (writeCharacteristic != null) {
        String commandWithNewline = '$command\n';
        List<int> bytes = commandWithNewline.codeUnits;

        if (writeCharacteristic.properties.writeWithoutResponse) {
          await writeCharacteristic.write(bytes, withoutResponse: true);
        } else {
          await writeCharacteristic.write(bytes);
        }

        print('✅ ${device.platformName}에 명령 전송 성공: $command');
      } else {
        print('❌ ${device.platformName}에서 쓰기 가능한 특성을 찾을 수 없습니다.');
      }
    } catch (e) {
      print('❌ ${device.platformName}에 명령 전송 오류: $e');
    }
  }

  Future<void> _stopMeasurement() async {
    await _sendCommand('{"command": "stop"}');

    if (mounted) {
      setState(() {
        _isMeasuring = false;
        _currentPosture = '측정 완료';
      });
    }

    _calibrationTimer?.cancel();
    _measurementTimer?.cancel();
    _dataWindowTimer?.cancel();

    print('측정 완료 - 총 ${_measurementData.length}개 데이터 수집');
  }

  void _connectToServer() {
    try {
      print('WebSocket 서버 연결 시도: ws://3.34.159.75:8000/ws');

      _webSocket = WebSocketChannel.connect(
        Uri.parse('ws://3.34.159.75:8000/ws'),
      );

      print('WebSocket 연결 시도 중...');

      if (mounted) {
        setState(() {
          _isSocketConnected = true;
          _serverPosture = '서버 연결됨 - 데이터 대기 중';
        });
      }
      print('✅ WebSocket 서버에 연결되었습니다.');

      _webSocket!.stream.listen(
        (message) {
          print('서버로부터 메시지 수신: $message');
          try {
            Map<String, dynamic> data = jsonDecode(message);
            _handleServerPrediction(data);
          } catch (e) {
            print('서버 응답 파싱 오류: $e');
          }
        },
        onError: (error) {
          print('❌ WebSocket 오류: $error');
          if (mounted) {
            setState(() {
              _isSocketConnected = false;
              _serverPosture = '연결 오류: $error';
            });
          }
        },
        onDone: () {
          print('❌ WebSocket 연결이 끊어졌습니다.');
          if (mounted) {
            setState(() {
              _isSocketConnected = false;
              _serverPosture = '서버 연결 끊어짐';
            });
          }
        },
      );
    } catch (e) {
      print('WebSocket 연결 설정 오류: $e');
      if (mounted) {
        setState(() {
          _isSocketConnected = false;
          _serverPosture = '연결 설정 실패: $e';
        });
      }
    }
  }

  void _sendDataToServer(Map<String, dynamic> data) {
    if (_webSocket != null && _isSocketConnected) {
      String jsonData = jsonEncode(data);
      _webSocket!.sink.add(jsonData);
      print('📤 서버로 데이터 전송: $jsonData');
    }
  }

  void _handleServerPrediction(dynamic data) {
    try {
      print('📥 서버로부터 예측 결과 수신: $data');

      if (data is Map) {
        int posture = data['posture'] ?? 0;
        double confidence = (data['confidence']?.toDouble() ?? 0.0) * 100;

        if (mounted) {
          setState(() {
            _serverPosture = _getPostureText(posture);
            _confidence = confidence;

            if (_isMeasuring) {
              if (_measurementData.isEmpty) {
                _currentPosture = '0번 자세 (정자세)';
              } else {
                _currentPosture =
                    '${posture}번 자세 (${_getPostureText(posture)})';
              }
            } else {
              _currentPosture = _serverPosture;
            }
          });
        }

        print(
          '📊 최종 자세 예측 결과: $_serverPosture (신뢰도: ${confidence.toStringAsFixed(1)}%)',
        );
      }
    } catch (e) {
      print('서버 응답 처리 오류: $e');
    }
  }

  String _getPostureText(int postureIndex) {
    switch (postureIndex) {
      case 0:
        return '정자세';
      case 1:
        return '거북목';
      case 2:
        return '왼쪽 기울임';
      case 3:
        return '오른쪽 기울임';
      case 4:
        return '앞으로 숙임';
      case 5:
        return '뒤로 젖힘';
      case 6:
        return '복합 자세';
      case 7:
        return '심한 불량 자세';
      default:
        return '알 수 없음';
    }
  }

  @override
  void dispose() {
    _imuSubscription?.cancel();
    _fsrSubscription?.cancel();
    _imuDevice?.disconnect();
    _fsrDevice?.disconnect();
    _calibrationTimer?.cancel();
    _measurementTimer?.cancel();
    _dataWindowTimer?.cancel();
    _pulseController.dispose();
    _rotationController.dispose();
    _webSocket?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color currentColor = _getCurrentColor();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFFF0F7FF), const Color(0xFFF8FAFC)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 상단 바
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A90E2).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back_ios,
                          color: Color(0xFF4A90E2),
                          size: 20,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '🧘‍♀️ 자세 측정',
                        style: TextStyle(
                          color: const Color(0xFF2D3748),
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Container(width: 48),
                  ],
                ),
              ),

              // 메인 콘텐츠
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // 주간 통계 버튼
                      _buildReportButton(),

                      const SizedBox(height: 20),

                      // 스캔 및 장치 목록 - 모든 모듈이 연결되지 않은 경우 표시
                      if (_imuDevice == null || _fsrDevice == null)
                        _buildScanSection(),

                      // 모듈 상태 카드 (하나라도 연결되었을 때)
                      if (_isConnected) _buildModuleStatusCard(),

                      const SizedBox(height: 20),

                      // 측정 카드
                      if (_isConnected) _buildMeasurementCard(currentColor),

                      const SizedBox(height: 20),

                      // 서버 연결 상태
                      if (_isConnected) _buildServerStatusCard(),

                      const SizedBox(height: 20),

                      // 측정 버튼
                      if (_isConnected) _buildMeasurementButton(currentColor),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScanSection() {
    return Column(
      children: [
        // 스캔 컨트롤 카드
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4A90E2).withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(
              color: const Color(0xFF4A90E2).withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A90E2).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _isScanning ? Icons.bluetooth_searching : Icons.bluetooth,
                      color: const Color(0xFF4A90E2),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📡 블루투스 장치 스캔',
                          style: TextStyle(
                            color: const Color(0xFF2D3748),
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isScanning
                              ? '주변 장치를 검색하고 있습니다...'
                              : _getConnectionStatusText(),
                          style: TextStyle(
                            color: const Color(0xFF718096),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isScanning ? null : _startScan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A90E2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isScanning ? Icons.hourglass_empty : Icons.search,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isScanning ? '스캔 중...' : '장치 스캔 시작',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 장치 목록
        if (_devicesList.isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📱 발견된 장치 (${_devicesList.length}개)',
                  style: TextStyle(
                    color: const Color(0xFF2D3748),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A90E2).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: const Color(0xFF4A90E2),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _getNextConnectionInfo(),
                          style: TextStyle(
                            color: const Color(0xFF4A90E2),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ...List.generate(_devicesList.length, (index) {
                  BluetoothDevice device = _devicesList[index];
                  String deviceName =
                      device.platformName.isNotEmpty
                          ? device.platformName
                          : '이름 없음';
                  bool isHC06 =
                      deviceName.toUpperCase().contains('HC-06') ||
                      deviceName.toUpperCase().contains('HC06');

                  // 이미 연결된 장치인지 확인
                  bool isAlreadyConnected =
                      (_imuDevice?.remoteId.str == device.remoteId.str) ||
                      (_fsrDevice?.remoteId.str == device.remoteId.str);

                  // 연결 가능한지 확인
                  bool canConnect =
                      !isAlreadyConnected &&
                      (_imuDevice == null || _fsrDevice == null);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap:
                            (_isConnecting || !canConnect)
                                ? null
                                : () => _connectToDevice(device),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color:
                                isHC06
                                    ? const Color(0xFF48BB78).withOpacity(0.05)
                                    : const Color(0xFFF7FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  isHC06
                                      ? const Color(0xFF48BB78).withOpacity(0.3)
                                      : const Color(0xFFE2E8F0),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color:
                                      isHC06
                                          ? const Color(
                                            0xFF48BB78,
                                          ).withOpacity(0.1)
                                          : const Color(
                                            0xFF4A90E2,
                                          ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  isHC06 ? Icons.star : Icons.bluetooth,
                                  color:
                                      isHC06
                                          ? const Color(0xFF48BB78)
                                          : const Color(0xFF4A90E2),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            deviceName,
                                            style: TextStyle(
                                              color: const Color(0xFF2D3748),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isHC06) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF48BB78),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'HC-06',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (isAlreadyConnected) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF4A90E2),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              _getDeviceConnectionStatus(
                                                device,
                                              ),
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      device.remoteId.str,
                                      style: TextStyle(
                                        color: const Color(0xFF718096),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios,
                                color: const Color(0xFF9CA3AF),
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildModuleStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A90E2).withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: const Color(0xFF4A90E2).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A90E2).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.sensors,
                  color: const Color(0xFF4A90E2),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📡 센서 모듈 상태',
                      style: TextStyle(
                        color: const Color(0xFF2D3748),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'IMU: ${_imuDevice?.platformName ?? "연결 안됨"} | FSR: ${_fsrDevice?.platformName ?? "연결 안됨"}',
                      style: TextStyle(
                        color: const Color(0xFF718096),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // IMU 모듈 상태
          _buildModuleStatusItem(
            '🎯 IMU 센서',
            '자세 각도 측정',
            _imuConnected,
            _imuStatus,
          ),

          const SizedBox(height: 12),

          // FSR 모듈 상태
          _buildModuleStatusItem(
            '⚖️ FSR 센서',
            '압력 분포 측정',
            _fsrConnected,
            _fsrStatus,
          ),

          const SizedBox(height: 16),

          // 전체 상태 표시
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:
                  _modulesReady
                      ? const Color(0xFF48BB78).withOpacity(0.1)
                      : const Color(0xFFED8936).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    _modulesReady
                        ? const Color(0xFF48BB78).withOpacity(0.3)
                        : const Color(0xFFED8936).withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _modulesReady ? Icons.check_circle : Icons.warning,
                  color:
                      _modulesReady
                          ? const Color(0xFF48BB78)
                          : const Color(0xFFED8936),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _modulesReady
                        ? '✅ 모든 모듈 준비 완료 - 측정 가능'
                        : '⏳ 모듈 준비 중... 잠시만 기다려주세요',
                    style: TextStyle(
                      color:
                          _modulesReady
                              ? const Color(0xFF48BB78)
                              : const Color(0xFFED8936),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleStatusItem(
    String title,
    String subtitle,
    bool connected,
    String status,
  ) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (!connected) {
      statusColor = const Color(0xFF9CA3AF);
      statusIcon = Icons.sensors_off;
      statusText = '연결 안됨';
    } else if (status == 'ready') {
      statusColor = const Color(0xFF48BB78);
      statusIcon = Icons.check_circle;
      statusText = '준비 완료';
    } else if (status == 'connected') {
      statusColor = const Color(0xFFED8936);
      statusIcon = Icons.hourglass_empty;
      statusText = '준비 중';
    } else {
      statusColor = const Color(0xFFE53E3E);
      statusIcon = Icons.error;
      statusText = '오류';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.2), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(statusIcon, color: statusColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: const Color(0xFF2D3748),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: const Color(0xFF718096),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeasurementCard(Color currentColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: currentColor.withOpacity(0.15),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
        border: Border.all(color: currentColor.withOpacity(0.2), width: 2),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: currentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _isCalibrating ? '🎯 캘리브레이션' : '📊 실시간 측정',
              style: TextStyle(
                color: currentColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 24),

          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [currentColor.withOpacity(0.8), currentColor],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: currentColor.withOpacity(0.3),
                        blurRadius: 25,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isCalibrating)
                          Column(
                            children: [
                              Text(
                                '$_calibrationCountdown',
                                style: TextStyle(
                                  color: currentColor,
                                  fontSize: 56,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '초',
                                style: TextStyle(
                                  color: currentColor.withOpacity(0.7),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        else ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: currentColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _currentPosture,
                              style: TextStyle(
                                color: currentColor,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${_confidence.toInt()}%',
                            style: TextStyle(
                              color: currentColor,
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -1.0,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _buildServerStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: (_isSocketConnected
                    ? const Color(0xFF48BB78)
                    : const Color(0xFFED8936))
                .withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color:
              _isSocketConnected
                  ? const Color(0xFF48BB78).withOpacity(0.3)
                  : const Color(0xFFED8936).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (_isSocketConnected
                      ? const Color(0xFF48BB78)
                      : const Color(0xFFED8936))
                  .withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _isSocketConnected ? Icons.cloud_done : Icons.cloud_off,
              color:
                  _isSocketConnected
                      ? const Color(0xFF48BB78)
                      : const Color(0xFFED8936),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _isSocketConnected ? '🟢 서버 연결됨' : '🔴 서버 연결 안됨',
                      style: TextStyle(
                        color: const Color(0xFF2D3748),
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: (_isSocketConnected
                                ? const Color(0xFF48BB78)
                                : const Color(0xFFED8936))
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _isSocketConnected ? 'AI 분석 중' : '연결 필요',
                        style: TextStyle(
                          color:
                              _isSocketConnected
                                  ? const Color(0xFF48BB78)
                                  : const Color(0xFFED8936),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _serverPosture,
                  style: TextStyle(
                    color: const Color(0xFF718096),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeasurementButton(Color currentColor) {
    bool canStartMeasurement =
        _isSocketConnected && _isConnected && _modulesReady;

    String buttonText =
        _isMeasuring
            ? '⏹️ 측정 중지'
            : !_isConnected
            ? '📱 블루투스 연결 필요'
            : !_isSocketConnected
            ? '🌐 서버 연결 필요'
            : !_modulesReady
            ? '📡 모듈 준비 필요'
            : '🚀 측정 시작';

    Color buttonColor =
        _isMeasuring
            ? const Color(0xFFED8936)
            : canStartMeasurement
            ? const Color(0xFF4A90E2)
            : const Color(0xFF9CA3AF);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: buttonColor.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap:
              canStartMeasurement || _isMeasuring
                  ? (_isMeasuring ? _stopMeasurement : _startMeasurement)
                  : null,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [buttonColor, buttonColor.withOpacity(0.8)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _isMeasuring
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  buttonText,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getCurrentColor() {
    if (_isCalibrating) return const Color(0xFF4A90E2);
    if (!_isSocketConnected) return const Color(0xFFED8936);

    if (_currentPosture.contains('정자세') || _currentPosture.contains('0번 자세')) {
      return const Color(0xFF48BB78);
    } else if (_currentPosture.contains('번 자세')) {
      return const Color(0xFFE53E3E);
    }

    if (_confidence > 80) return const Color(0xFF48BB78);
    if (_confidence > 60) return const Color(0xFF4A90E2);
    return const Color(0xFFED8936);
  }

  Widget _buildReportButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF48BB78).withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ReportScreen()),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [const Color(0xFF48BB78), const Color(0xFF38A169)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.analytics_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  '📊 주간 통계 보기',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
