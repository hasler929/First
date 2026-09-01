import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

void main() => runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ExhaustAppScreen(),
    ));

class KalmanRpmFilter {
  double _rpm = 1000.0;
  double _velocity = 0.0;
  double _p00 = 1.0, _p01 = 0.0, _p10 = 0.0, _p11 = 1.0;

  double predict(double dt) {
    _rpm += _velocity * dt;
    _p00 += dt * (_p10 + _p01 + dt * _p11) + (400.0 * dt);
    _p01 += dt * _p11;
    _p10 += dt * _p11;
    _p11 += 400.0 * dt;
    return _rpm.clamp(0.0, 9000.0);
  }

  void update(double measured, double dt) {
    if (dt <= 0) return;
    double y = measured - _rpm;
    double s = _p00 + 50.0;
    double k0 = _p00 / s;
    double k1 = _p10 / s;
    _rpm += k0 * y;
    _velocity += k1 * y;
    double p00 = _p00, p01 = _p01;
    _p00 -= k0 * p00;
    _p01 -= k0 * p01;
    _p10 -= k1 * p00;
    _p11 -= k1 * p01;
  }

  double get rpm => _rpm;
  double get velocity => _velocity;
}

class ExhaustAppScreen extends StatefulWidget {
  const ExhaustAppScreen({super.key});

  @override
  State<ExhaustAppScreen> createState() => _ExhaustAppScreenState();
}

class _ExhaustAppScreenState extends State<ExhaustAppScreen> {
  final KalmanRpmFilter _kalman = KalmanRpmFilter();
  final AudioPlayer _audio = AudioPlayer();
  Timer? _ticker;

  double _throttle = 0.0;
  double _mockRpm = 900.0;
  double _boost = -0.6;
  bool _isBackfire = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_throttle > 0) {
        _mockRpm = (_mockRpm + 80).clamp(900.0, 7800.0);
        _boost = (_boost + 0.04).clamp(-0.8, 1.5);
      } else {
        _mockRpm = (_mockRpm - 45).clamp(900.0, 7800.0);
        _boost = (_boost - 0.05).clamp(-0.8, 1.5);
      }

      _kalman.update(_mockRpm, 0.016);
      _kalman.predict(0.016);
      setState(() {});
    });
  }

  void _onGasDown() => setState(() => _throttle = 1.0);

  void _onGasUp() {
    setState(() {
      _throttle = 0.0;
      if (_kalman.rpm > 3500) {
        _isBackfire = true;
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _isBackfire = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0B0E),
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
                    style: TextStyle(
                      color: _boost > 0 ? Colors.cyanAccent : Colors.white38,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
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
                    width: 260,
                    height: 260,
                    child: CircularProgressIndicator(
                      value: (_kalman.rpm / 8000.0).clamp(0.0, 1.0),
                      strokeWidth: 16,
                      backgroundColor: Colors.white10,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _isBackfire
                            ? Colors.orangeAccent
                            : (_kalman.rpm > 6000 ? Colors.redAccent : Colors.cyanAccent),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _kalman.rpm.toInt().toString(),
                        style: const TextStyle(fontSize: 60, fontWeight: FontWeight.w900, color: Colors.white),
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
                  height: 70,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _throttle > 0 ? Colors.redAccent : Colors.white12,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'ПЕДАЛЬ ГАЗА (ЗАЖАТЬ)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
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
