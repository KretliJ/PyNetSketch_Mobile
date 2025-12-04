import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';

void main() {
  runApp(const PyNetSketchMobile());
}

class PyNetSketchMobile extends StatelessWidget {
  const PyNetSketchMobile({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PyNetSketch Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
          surface: const Color(0xFF121212),
        ),
      ),
      home: const DiscoveryScreen(),
    );
  }
}

// --- SCREEN 1: AUTO DISCOVERY ---
class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final List<Map<String, dynamic>> _probes = [];
  bool _isScanning = false;
  String _scanStatus = "Ready";
  RawDatagramSocket? _udpSocket;

  // Interface selection
  List<String> _availableIps = [];
  String? _selectedSourceIp;

  @override
  void initState() {
    super.initState();
    _refreshLocalIps();
  }

  @override
  void dispose() {
    _udpSocket?.close();
    super.dispose();
  }

  Future<void> _refreshLocalIps() async {
    try {
      List<String> ips = [];
      List<NetworkInterface> interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback) {
            ips.add(addr.address);
          }
        }
      }

      if (mounted) {
        setState(() {
          _availableIps = ips;
          // Auto-select the first private IP (usually 192.168... or 10...)
          if (_selectedSourceIp == null && ips.isNotEmpty) {
            _selectedSourceIp = ips.firstWhere(
              (ip) =>
                  ip.startsWith("192") ||
                  ip.startsWith("10") ||
                  ip.startsWith("172"),
              orElse: () => ips.first,
            );
          }
        });
        // Start listening immediately after finding IP
        if (_selectedSourceIp != null) startDiscovery();
      }
    } catch (e) {
      debugPrint("Error getting IPs: $e");
    }
  }

  Future<void> startDiscovery() async {
    if (_selectedSourceIp == null) {
      setState(() => _scanStatus = "No Network Interface Selected");
      return;
    }

    setState(() {
      _probes.clear();
      _isScanning = true;
      _scanStatus = "Listening on $_selectedSourceIp...";
    });

    try {
      _udpSocket?.close();

      // BIND SPECIFICALLY TO THE SELECTED IP
      // This helps ensure we are using the correct network interface
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress(_selectedSourceIp!),
        0,
      );
      _udpSocket!.broadcastEnabled = true;

      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final Datagram? dg = _udpSocket!.receive();
          if (dg != null) {
            try {
              final String msg = utf8.decode(dg.data);
              final data = jsonDecode(msg);
              final existingIndex = _probes.indexWhere(
                (p) => p['ip'] == data['ip'],
              );
              if (existingIndex == -1) {
                setState(() {
                  _probes.add(data);
                });
              }
            } catch (e) {
              // Ignore garbage
            }
          }
        }
      });

      final data = utf8.encode("PYNET_DISCOVER");

      // 1. Broadcast to 255.255.255.255 (Local Subnet)
      try {
        _udpSocket!.send(data, InternetAddress("255.255.255.255"), 5051);
      } catch (e) {
        debugPrint("Broadcast error: $e");
      }

      // 2. Calculated Broadcast (e.g., 192.168.15.255)
      try {
        final parts = _selectedSourceIp!.split('.');
        if (parts.length == 4) {
          final broadcast = "${parts[0]}.${parts[1]}.${parts[2]}.255";
          _udpSocket!.send(data, InternetAddress(broadcast), 5051);
        }
      } catch (e) {
        debugPrint("Subnet broadcast error: $e");
      }

      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _isScanning && _scanStatus.contains("Listening")) {
          setState(() => _isScanning = false);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _scanStatus = "Bind Error: $e");
        _isScanning = false;
      }
    }
  }

  Future<void> _scanSpecificSubnet(String subnetPrefix) async {
    if (_selectedSourceIp == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Select source IP first")));
      return;
    }

    setState(() {
      _isScanning = true;
      _scanStatus = "Scanning $subnetPrefix.x from $_selectedSourceIp...";
    });

    RawDatagramSocket? senderSocket;
    try {
      // IMPORTANT: Bind to the specific WiFi IP.
      // If we bind to anyIPv4, Android might route 192.168.3.x via Cellular gateway.
      senderSocket = await RawDatagramSocket.bind(
        InternetAddress(_selectedSourceIp!),
        0,
      );
      final data = utf8.encode("PYNET_DISCOVER");

      int sentCount = 0;
      for (int i = 1; i < 255; i++) {
        if (!mounted || !_isScanning) break;

        final targetIp = "$subnetPrefix.$i";

        // Update UI occasionally
        if (i % 25 == 0) {
          setState(() => _scanStatus = "Pinging $targetIp...");
        }

        try {
          senderSocket.send(data, InternetAddress(targetIp), 5051);
          sentCount++;
        } catch (e) {
          debugPrint("Send failed to $targetIp: $e");
        }

        // Throttle slightly (1ms) to prevent buffer overflow
        if (i % 5 == 0) await Future.delayed(const Duration(milliseconds: 1));
      }
      debugPrint("Sent $sentCount packets via ${_selectedSourceIp}");
    } catch (e) {
      setState(() => _scanStatus = "Socket Error: $e");
    } finally {
      senderSocket?.close();
    }

    if (mounted) {
      setState(() => _scanStatus = "Waiting for replies...");
    }

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isScanning = false);
    });
  }

  void _showSubnetDialog() {
    // Attempt to guess subnet based on current IP but allow editing
    String defaultPrefix = "192.168.3";

    final subnetController = TextEditingController(text: defaultPrefix);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Scan Remote Subnet"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Send from: ${_selectedSourceIp ?? 'Unknown'}",
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "Enter target subnet prefix (e.g. 192.168.3)",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: subnetController,
              decoration: const InputDecoration(
                labelText: "Target Subnet",
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () {
              final prefix = subnetController.text.trim();
              if (prefix.isNotEmpty) {
                final cleanPrefix = prefix.endsWith('.')
                    ? prefix.substring(0, prefix.length - 1)
                    : prefix;
                Navigator.pop(ctx);
                _scanSpecificSubnet(cleanPrefix);
              }
            },
            child: const Text("Scan"),
          ),
        ],
      ),
    );
  }

  void _showManualConnectDialog() {
    final ipController = TextEditingController();
    bool isValidating = false;
    String? errorText;
    String? pingResult;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text("Manual Connect"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: ipController,
                    decoration: InputDecoration(
                      labelText: "Probe IP Address",
                      hintText: "e.g., 192.168.3.10",
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                    ),
                    keyboardType: TextInputType.number,
                    enabled: !isValidating,
                  ),
                  if (pingResult != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        pingResult!,
                        style: TextStyle(
                          fontSize: 12,
                          color: pingResult!.contains("Success")
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ),
                  if (isValidating)
                    const Padding(
                      padding: EdgeInsets.only(top: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text("Checking..."),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isValidating
                    ? null
                    : () async {
                        // Test Connectivity (Simple TCP connect to common port or probe port)
                        if (ipController.text.isEmpty) return;
                        setState(() {
                          isValidating = true;
                          pingResult = null;
                        });
                        try {
                          final socket = await Socket.connect(
                            ipController.text,
                            5050,
                            timeout: const Duration(seconds: 2),
                          );
                          socket.destroy();
                          setState(
                            () => pingResult = "Success: Probe Port 5050 Open",
                          );
                        } catch (e) {
                          setState(
                            () => pingResult = "Failed: Unreachable or Blocked",
                          );
                        } finally {
                          setState(() => isValidating = false);
                        }
                      },
                child: const Text("Test Ping"),
              ),
              FilledButton(
                onPressed: isValidating
                    ? null
                    : () async {
                        if (ipController.text.isEmpty) return;

                        setState(() {
                          isValidating = true;
                          errorText = null;
                        });

                        try {
                          final socket = await Socket.connect(
                            ipController.text,
                            5050,
                            timeout: const Duration(seconds: 5),
                          );

                          socket.write(jsonEncode({"action": "identify"}));

                          await for (final data in socket) {
                            final resp = jsonDecode(utf8.decode(data));
                            socket.destroy();

                            if (resp['status'] == 'ok') {
                              if (!mounted) return;
                              Navigator.pop(ctx);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ControlScreen(
                                    hostIp: ipController.text,
                                    sessionName:
                                        resp['session_name'] ?? "Manual Probe",
                                  ),
                                ),
                              );
                            } else {
                              setState(() => errorText = "Refused.");
                            }
                            break;
                          }
                        } on SocketException catch (e) {
                          setState(() => errorText = "Failed: ${e.message}");
                        } catch (e) {
                          setState(() => errorText = "Error: $e");
                        } finally {
                          if (mounted) setState(() => isValidating = false);
                        }
                      },
                child: const Text("Connect"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Select Probe"),
        actions: [
          IconButton(
            icon: const Icon(Icons.wifi_tethering),
            tooltip: "Scan Subnet",
            onPressed: _showSubnetDialog,
          ),
          IconButton(
            icon: const Icon(Icons.add_link),
            tooltip: "Manual Connect",
            onPressed: _showManualConnectDialog,
          ),
          _isScanning
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: startDiscovery,
                ),
        ],
      ),
      body: Column(
        children: [
          // IP SELECTOR BAR
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.black26,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("My IP:", style: TextStyle(color: Colors.grey)),
                DropdownButton<String>(
                  value: _selectedSourceIp,
                  dropdownColor: Colors.grey[900],
                  style: const TextStyle(color: Colors.cyanAccent),
                  underline: Container(height: 1, color: Colors.cyan),
                  items: _availableIps.map((ip) {
                    return DropdownMenuItem(value: ip, child: Text(ip));
                  }).toList(),
                  onChanged: (val) {
                    setState(() => _selectedSourceIp = val);
                    startDiscovery();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  onPressed: _refreshLocalIps,
                  tooltip: "Refresh IPs",
                ),
              ],
            ),
          ),

          Expanded(
            child: _probes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.radar, size: 80, color: Colors.grey),
                        const SizedBox(height: 20),
                        Text(
                          _isScanning ? _scanStatus : "No probes found.",
                          style: const TextStyle(color: Colors.grey),
                        ),
                        if (_isScanning)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              "Scanning remote subnet...",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        if (!_isScanning)
                          Wrap(
                            spacing: 10,
                            alignment: WrapAlignment.center,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: _showSubnetDialog,
                                icon: const Icon(Icons.saved_search),
                                label: const Text("Scan Subnet"),
                              ),
                              FilledButton.icon(
                                onPressed: _showManualConnectDialog,
                                icon: const Icon(Icons.keyboard),
                                label: const Text("IP Manually"),
                              ),
                            ],
                          ),
                        if (!_isScanning)
                          TextButton(
                            onPressed: startDiscovery,
                            child: const Text("Scan Local Again"),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _probes.length,
                    itemBuilder: (context, index) {
                      final probe = _probes[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: ListTile(
                          leading: const Icon(
                            Icons.dns,
                            color: Colors.cyanAccent,
                          ),
                          title: Text(probe['session_name'] ?? "Unknown"),
                          subtitle: Text("${probe['ip']}:${probe['port']}"),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ControlScreen(
                                  hostIp: probe['ip'],
                                  sessionName: probe['session_name'],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// --- SCREEN 2: CONTROL DASHBOARD ---
class ControlScreen extends StatefulWidget {
  final String hostIp;
  final String sessionName;

  const ControlScreen({
    super.key,
    required this.hostIp,
    required this.sessionName,
  });

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  final _targetController = TextEditingController(text: "8.8.8.8");
  bool _isBusy = false;
  bool _resolveDns = true;

  List<dynamic> _streamedResults = [];
  Map<String, dynamic>? _finalResult;
  String _lastAction = "";
  Socket? _currentSocket;

  // Timer related
  Timer? _timer;
  final Stopwatch _stopwatch = Stopwatch();
  String _elapsedDisplay = "0.0s";

  @override
  void dispose() {
    _currentSocket?.destroy();
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _stopwatch.reset();
    _stopwatch.start();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        _elapsedDisplay =
            "${(_stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s";
      });
    });
  }

  void _stopTimer() {
    _stopwatch.stop();
    _timer?.cancel();
  }

  void _stopCommand() {
    if (_currentSocket != null) {
      _currentSocket!.destroy();
      _stopTimer();
      setState(() {
        _isBusy = false;
        _currentSocket = null;
        if (_lastAction != 'traceroute') {
          _finalResult = {"status": "error", "message": "Stopped by user"};
        }
      });
    }
  }

  Future<void> _getProbeLogs() async {
    _sendCommand("get_logs", isLogRequest: true);
  }

  Future<void> _sendCommand(String action, {bool isLogRequest = false}) async {
    if (_isBusy) _stopCommand();

    setState(() {
      _isBusy = true;
      if (!isLogRequest) {
        _finalResult = null;
        _streamedResults = [];
        _lastAction = action;
        _elapsedDisplay = "0.0s";
        _startTimer();
      }
    });

    try {
      _currentSocket = await Socket.connect(
        widget.hostIp,
        5050,
        timeout: const Duration(seconds: 5),
      );

      final cmd = jsonEncode({
        "action": action,
        "target": _targetController.text,
        "resolve_dns": _resolveDns,
      });

      _currentSocket!.write(cmd);

      _currentSocket!.listen(
        (data) {
          final respStr = utf8.decode(data);
          final parts = respStr.split('\n').where((s) => s.trim().isNotEmpty);

          for (var part in parts) {
            try {
              final jsonResponse = jsonDecode(part);

              setState(() {
                if (isLogRequest) {
                  _showLogsDialog(
                    jsonResponse['result'] ??
                        jsonResponse['logs'] ??
                        "No logs returned.",
                  );
                  _isBusy = false;
                  _currentSocket?.destroy();
                } else if (jsonResponse['status'] == 'partial') {
                  _streamedResults.add(jsonResponse['data']);
                } else {
                  _finalResult = jsonResponse;
                  _isBusy = false;
                  _stopTimer();
                  _currentSocket?.destroy();
                }
              });
            } catch (e) {
              // Partial packet logic
            }
          }
        },
        onError: (e) {
          if (!isLogRequest) _handleError(e);
        },
        onDone: () {
          if (mounted) {
            _stopTimer();
            setState(() => _isBusy = false);
          }
        },
      );
    } catch (e) {
      if (!isLogRequest)
        _handleError(e);
      else {
        setState(() => _isBusy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to fetch logs: $e")));
      }
    }
  }

  void _showLogsDialog(String logs) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Probe Logs"),
        content: SingleChildScrollView(
          child: Text(
            logs,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  void _handleError(dynamic e) {
    _stopTimer();
    setState(() {
      _finalResult = {"status": "error", "message": e.toString()};
      _isBusy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sessionName),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: "View Probe Logs",
            onPressed: _isBusy ? null : _getProbeLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          // Input Area
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black26,
            child: Column(
              children: [
                TextField(
                  controller: _targetController,
                  decoration: const InputDecoration(
                    labelText: "Target (IP, Domain or CIDR)",
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.my_location),
                    hintText: "e.g., 192.168.1.0/24 for Net Scan",
                  ),
                ),
                const SizedBox(height: 10),

                // Controls Row
                Row(
                  children: [
                    const Text("Resolve DNS"),
                    Switch(
                      value: _resolveDns,
                      onChanged: _isBusy
                          ? null
                          : (v) => setState(() => _resolveDns = v),
                    ),
                    const Spacer(),
                    if (_isBusy)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _stopCommand,
                        icon: const Icon(Icons.stop),
                        label: const Text("STOP"),
                      ),
                  ],
                ),

                const SizedBox(height: 10),
                // Action Buttons Grid
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ActionButton(
                      icon: Icons.network_check,
                      label: "Ping",
                      onTap: _isBusy ? null : () => _sendCommand("ping"),
                    ),
                    _ActionButton(
                      icon: Icons.radar,
                      label: "Port Scan",
                      onTap: _isBusy ? null : () => _sendCommand("scan_ports"),
                    ),
                    _ActionButton(
                      icon: Icons.alt_route,
                      label: "Trace",
                      onTap: _isBusy ? null : () => _sendCommand("traceroute"),
                    ),
                    _ActionButton(
                      icon: Icons.lan,
                      label: "Net Scan",
                      onTap: _isBusy ? null : () => _sendCommand("arp_scan"),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Result Area
          Expanded(child: _buildResultView()),
        ],
      ),
    );
  }

  Widget _buildResultView() {
    // 0. LOADING STATE WITH TIMER
    if (_isBusy && _streamedResults.isEmpty && _finalResult == null) {
      return Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            const SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(strokeWidth: 6),
            ),
            Text(
              _elapsedDisplay,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (_finalResult != null && _finalResult!['status'] == 'error') {
      return Center(
        child: Text(
          "Error: ${_finalResult!['message']}",
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    // 1. PING VIEW
    if (_lastAction == 'ping' && _finalResult != null) {
      final data = _finalResult!['result'];
      final bool online = data['online'];
      final double rtt = data['rtt'] is int
          ? (data['rtt'] as int).toDouble()
          : data['rtt'];

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              online ? Icons.check_circle : Icons.error,
              size: 80,
              color: online ? Colors.green : Colors.red,
            ),
            const SizedBox(height: 10),
            Text(
              online ? "HOST ONLINE" : "HOST OFFLINE",
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            if (online)
              Text(
                "${rtt.toStringAsFixed(1)} ms",
                style: const TextStyle(fontSize: 18, color: Colors.grey),
              ),
            const SizedBox(height: 20),
            Text(
              "Finished in $_elapsedDisplay",
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // 2. PORT SCAN VIEW
    if (_lastAction == 'scan_ports') {
      final List ports = _streamedResults.isNotEmpty
          ? _streamedResults
          : (_finalResult != null ? _finalResult!['result'] : []);
      if (ports.isEmpty && !_isBusy)
        return const Center(child: Text("No open ports found."));

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              "Port Scan Results ($_elapsedDisplay)",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: ports.length,
              itemBuilder: (ctx, i) => Card(
                color: Colors.green.withOpacity(0.1),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.login, color: Colors.green),
                  title: Text(ports[i].toString()),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // 3. TRACEROUTE VIEW
    if (_lastAction == 'traceroute') {
      final List hops = _finalResult != null
          ? _finalResult!['result']
          : _streamedResults;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              "Traceroute ($_elapsedDisplay)",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: hops.length + (_isBusy ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == hops.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final hop = hops[i];
                final bool isTimeout = hop['ip'] == '*';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isTimeout
                        ? Colors.grey
                        : Colors.blueAccent,
                    child: Text(
                      "${hop['ttl']}",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(isTimeout ? "Request Timed Out" : hop['ip']),
                  subtitle: isTimeout
                      ? null
                      : Text(
                          "${hop['hostname'] ?? ''} • ${(hop['time'] ?? 0).toStringAsFixed(1)}ms",
                        ),
                  dense: true,
                );
              },
            ),
          ),
        ],
      );
    }

    // 4. ARP / NETWORK SCAN VIEW (New)
    if (_lastAction == 'arp_scan') {
      final List devices = _streamedResults.isNotEmpty
          ? _streamedResults
          : (_finalResult != null ? _finalResult!['result'] : []);
      if (devices.isEmpty && !_isBusy)
        return const Center(child: Text("No devices found in this range."));

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              "Network Devices found: ${devices.length} ($_elapsedDisplay)",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: devices.length,
              itemBuilder: (ctx, i) {
                final dev = devices[i];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: ListTile(
                    leading: const Icon(
                      Icons.devices,
                      color: Colors.orangeAccent,
                    ),
                    title: Text(dev['ip'] ?? "Unknown IP"),
                    subtitle: Text(
                      "${dev['mac'] ?? ''}\n${dev['vendor'] ?? ''}",
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return const Center(
      child: Text("Ready to scan.", style: TextStyle(color: Colors.grey)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconButton.filledTonal(
          onPressed: onTap,
          icon: Icon(icon),
          tooltip: label,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10),
        ), // Smaller text to fit 4 items
      ],
    );
  }
}
