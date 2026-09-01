import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

void main() => runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ExhaustAppScreen(),
    ));

class EngineAudioSynth {
  final AudioPlayer _enginePlayer = AudioPlayer();
  final AudioPlayer _popPlayer = AudioPlayer();
  bool _isReady = false;

  Future<void> init() async {
    await _enginePlayer.setReleaseMode(ReleaseMode.loop);
    await _popPlayer.setReleaseMode(ReleaseMode.stop);
    await loadEnginePreset('V8');
    _isReady = true;
  }

  Future<void> loadEnginePreset(String type) async {
    int sampleRate = 22050;
    double duration = 1.2;
    int numSamples = (sampleRate * duration).toInt();

    double baseFreq = (type == 'V8') ? 38.0 : (type == 'V10' ? 52.0 : 44.0);

    var pcmBytes = BytesBuilder();
    Random rnd = Random();

    for (int i = 0; i < numSamples; i++) {
      double t = i / sampleRate;
      double wave = sin(2 * pi * baseFreq * t) * 0.45;
      wave += sin(2 * pi * baseFreq * 2.0 * t) * 0.25;
      wave += sin(2 * pi * baseFreq * 4.0 * t) * 0.15;
      
      double noise = (rnd.nextDouble() * 2 - 1) * 0.08;
      wave = (wave + noise).clamp(-1.0, 1.0);

      if (wave > 0.3) wave = 0.3 + (wave - 0.3) * 0.5;

      int sample = (wave * 32767).toInt();
      pcmBytes.addByte(sample & 0xFF);
      pcmBytes.addByte((sample >> 8) & 0xFF);
    }

    Uint8List wavData = _createWavHeader(pcmBytes.toBytes(), sampleRate, 1, 16);
    await _enginePlayer.setSource(BytesSource(wavData));
    await _enginePlayer.setVolume(1.0);
    await _enginePlayer.resume();
  }

  Future<void> playPop(double intensity) async {
    int sampleRate = 22050;
    double duration = 0.18;
    int numSamples = (sampleRate * duration).toInt();

    var pcmBytes = BytesBuilder();
    Random rnd = Random();

    for (int i = 0; i < numSamples; i++) {
      double t = i / sampleRate;
      double decay = exp(-t * 22.0);
      double noise = (rnd.nextDouble() * 2 - 1) * decay;
      int sample = (noise * 32767 * intensity).toInt().clamp(-32768, 32767);
      pcmBytes.addByte(sample & 0xFF);
      pcmBytes.addByte((sample >> 8) & 0xFF);
    }

    Uint8List popWav = _createWavHeader(pcmBytes.toBytes(), sampleRate, 1, 16);
    await _popPlayer.play(BytesSource(popWav), volume: intensity.clamp(0.2, 1.0));
  }

  void updateSound(double rpm, double throttle, double masterVol) {
    if (!_isReady) return;
    double rate = (rpm / 1800.0).clamp(0.5, 3.8);
    _enginePlayer.setPlaybackRate(rate);

    double volume = (0.35 + (throttle * 0.65)) * masterVol;
    _enginePlayer.setVolume(volume.clamp(0.0, 1.0));
  }

  Uint8List _createWavHeader(Uint8List pcm, int sampleRate, int channels, int bitsPerSample) {
    int fileSize = 36 + pcm.length;
    int byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    int blockAlign = channels * (bitsPerSample ~/ 8);

    var header = ByteData(44);
    header.setUint8(0, 0x52); header.setUint8(1, 0x49); header.setUint8(2, 0x46); header.setUint8(3, 0x46);
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57); header.setUint8(9, 0x41); header.setUint8(10, 0x56); header.setUint8(11, 0x45);
    header.setUint8(12, 0x66); header.setUint8(13, 0x6D); header.setUint8(14, 0x74); header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    header.setUint8(36, 0x64); header.setUint8(37, 0x61); header.setUint8(38, 0x74); header.setUint8(39, 0x61);
    header.setUint32(40, pcm.length, Endian.little);

    var full = BytesBuilder();
    full.add(header.buffer.asUint8List());
    full.add(pcm);
    return full.toBytes();
  }

  void dispose() {
    _enginePlayer.dispose();
    _popPlayer.dispose();
  }
}

class ExhaustAppScreen extends StatefulWidget {
  const ExhaustAppScreen({super.key});

  @override
  State<ExhaustAppScreen> createState() => _ExhaustAppScreenState();
}

class _ExhaustAppScreenState extends State<ExhaustAppScreen> {
  final EngineAudioSynth _synth = EngineAudioSynth();
  Timer? _ticker;

  String _selectedEngine = 'V8';
  double _rpm = 900.0;
  double _maxRpm = 8000.0;
  double _throttle = 0.0;
  double _boost = -0.5;
  double _masterVolume = 1.0;
  bool _popsEnabled = true;
  bool _isBackfire = false;

  @override
  void initState() {
    super.initState();
    _synth.init();

    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_throttle > 0) {
        _rpm = (_rpm + 95).clamp(900.0, _maxRpm);
        _boost = (_boost + 0.05).clamp(-0.8, 1.8);
      } else {
        _rpm = (_rpm - 55).clamp(900.0, _maxRpm);
        _boost = (_boost - 0.07).clamp(-0.8, 1.8);
      }

      _synth.updateSound(_rpm, _throttle, _masterVolume);
      setState(() {});
    });
  }

  void _onGasDown() => setState(() => _throttle = 1.0);

  void _onGasUp() {
    setState(() {
      _throttle = 0.0;
      if (_popsEnabled && _rpm > 3500) {
        _isBackfire = true;
        _synth.playPop((_rpm / _maxRpm).clamp(0.4, 1.0));
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) setState(() => _isBackfire = false);
        });
      }
    });
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF15171E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚙️ НАСТРОЙКИ СИМУЛЯТОРА', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const Divider(color: Colors.white12, height: 24),
                const Text('Тип двигателя:', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                Row(
                  children: ['V8', 'Turbo I4', 'V10'].map((engine) {
                    bool isSel = _selectedEngine == engine;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedEngine = engine);
                          setModalState(() {});
                          _synth.loadEnginePreset(engine);
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isSel ? Colors.redAccent : Colors.white10,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(engine, style: TextStyle(color: isSel ? Colors.white : Colors.white60, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Общая громкость:', style: TextStyle(color: Colors.white70)),
                    Text('${(_masterVolume * 100).toInt()}%', style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: _masterVolume,
                  min: 0.0,
                  max: 1.0,
                  activeColor: Colors.cyanAccent,
                  onChanged: (val) {
                    setState(() => _masterVolume = val);
                    setModalState(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Отстрелы выхлопа (Pop & Bang)', style: TextStyle(color: Colors.white70)),
                  value: _popsEnabled,
                  activeColor: Colors.orangeAccent,
                  onChanged: (val) {
                    setState(() => _popsEnabled = val);
                    setModalState(() {});
                  },
                ),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _synth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0B0E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('EXHAUST SIM (${_selectedEngine})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(icon: const Icon(Icons.settings, color: Colors.white70), onPressed: _openSettings),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'BOOST: ${_boost >= 0 ? "+" : ""}${_boost.toStringAsFixed(2)} BAR',
                    style: TextStyle(color: _boost > 0 ? Colors.cyanAccent : Colors.white38, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    'THROTTLE: ${(_throttle * 100).toInt()}%',
                    style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              const Spacer(),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 250,
                    height: 250,
                    child: CircularProgressIndicator(
                      value: (_rpm / _maxRpm).clamp(0.0, 1.0),
                      strokeWidth: 18,
                      backgroundColor: Colors.white10,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _isBackfire
                            ? Colors.orangeAccent
                            : (_rpm > 6500 ? Colors.redAccent : (_rpm > 4000 ? Colors.amberAccent : Colors.cyanAccent)),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _rpm.toInt().toString(),
                        style: const TextStyle(fontSize: 60, fontWeight: FontWeight.w900, color: Colors.white, fontFamily: 'monospace'),
                      ),
                      Text(
                        _isBackfire ? '🔥 POP & BANG 🔥' : 'RPM',
                        style: TextStyle(
                          color: _isBackfire ? Colors.orangeAccent : Colors.white38,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              GestureDetector(
                onTapDown: (_) => _onGasDown(),
                onTapUp: (_) => _onGasUp(),
                onTapCancel: () => _onGasUp(),
                child: Container(
                  height: 75,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _throttle > 0 ? Colors.redAccent : Colors.white12,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _throttle > 0 ? Colors.redAccent : Colors.white24, width: 2),
                    boxShadow: _throttle > 0
                        ? [BoxShadow(color: Colors.redAccent.withOpacity(0.5), blurRadius: 25, spreadRadius: 2)]
                        : [],
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'УДЕРЖИВАЙТЕ ГАЗ (GAS PEDAL)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
