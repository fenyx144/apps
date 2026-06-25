// lib/screens/splash_screen.dart (actualizado)
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gc_puesto_mercado_tienda/screens/login_screen.dart';
import 'package:gc_puesto_mercado_tienda/services/catalog_service.dart';
import 'package:get/get.dart';

import 'dashboard_screen.dart';


class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _glowController;
  late AnimationController _shimmerController;

  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _shimmerAnimation;
  Object _providerKey = UniqueKey();
  
  @override
  void initState() {
    super.initState();

    // ⭐ Controlador del logo
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // ⭐ Controlador del brillo pulsante
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // ⭐ Controlador del efecto shimmer
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    // Animación de escala del logo (suave y elegante)
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.0,
          end: 1.08,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 65.0,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.08,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 35.0,
      ),
    ]).animate(_logoController);

    // Fade in del logo
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeIn),
      ),
    );

    // ⭐ Brillo pulsante suave
    _glowAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.4,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50.0,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 0.6,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50.0,
      ),
    ]).animate(_glowController);

    // ⭐ Shimmer (destello que cruza)
    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    // Iniciar animaciones
    _logoController.forward();

    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        _glowController.repeat(reverse: true);
      }
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        _shimmerController.forward();
      }
    });

    // Navegar
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) {
        Get.off(
          () => const LoginScreen(), // LoginScreen(), //
          transition: Transition.fadeIn,
          duration: const Duration(milliseconds: 800),
        );
      }
    });
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final catalogService = context.read<CatalogService>();

    bool hasInternet = await _hasInternetConnection();

    if (hasInternet) {
      await catalogService.downloadCatalogos(
        tablas: [
          'laboratorios',
          'emp_trans',
          'muestras',
          'paquetes',
          'analisis',
          
        ],
      );
    } else {
      await catalogService.loadFromPrefs();
    }

    // Ir a login después de 2600ms o cuando termine (lo que tarde más)
    await Future.delayed(const Duration(milliseconds: 2600));

    if (mounted) {
      Get.off(
        () => const LoginScreen(), 
        transition: Transition.fadeIn,
        duration: const Duration(milliseconds: 800),
      );
    }
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _glowController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A2B56), Color(0xFF2D3E50), Color(0xFF4A90E2)],
          ),
        ),
        child: Stack(
          children: [
            // ⭐ Anillos sutiles de fondo
            Center(
              child: AnimatedBuilder(
                animation: _glowController,
                builder: (context, child) {
                  return CustomPaint(
                    size: Size(
                      MediaQuery.of(context).size.width,
                      MediaQuery.of(context).size.height,
                    ),
                    painter: SubtleRingsPainter(_glowAnimation.value),
                  );
                },
              ),
            ),

            // Logo y contenido principal
            Center(
              child: AnimatedBuilder(
                animation: _logoController,
                builder: (context, child) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ⭐ Logo con shimmer
                      Transform.scale(
                        scale: _scaleAnimation.value,
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Contenedor del logo
                              Container(
                                width: 140,
                                height: 140,
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(32),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.2),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 30,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: Image.asset(
                                  'assets/images/logo_grs.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(
                                      Icons.store,
                                      size: 60,
                                      color: Colors.white,
                                    );
                                  },
                                ),
                              ),

                              // ⭐ Brillo pulsante alrededor del logo
                              AnimatedBuilder(
                                animation: _glowController,
                                builder: (context, child) {
                                  return Container(
                                    width: 140,
                                    height: 140,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(32),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF6BA3E8)
                                              .withOpacity(
                                                _glowAnimation.value * 0.4,
                                              ),
                                          blurRadius: 40 * _glowAnimation.value,
                                          spreadRadius:
                                              8 * _glowAnimation.value,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),

                              // ⭐ Efecto shimmer que cruza
                              AnimatedBuilder(
                                animation: _shimmerController,
                                builder: (context, child) {
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(32),
                                    child: ShaderMask(
                                      shaderCallback: (bounds) {
                                        return LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Colors.transparent,
                                            Colors.white.withOpacity(0.3),
                                            Colors.transparent,
                                          ],
                                          stops: [
                                            (_shimmerAnimation.value - 0.3)
                                                .clamp(0.0, 1.0),
                                            _shimmerAnimation.value.clamp(
                                              0.0,
                                              1.0,
                                            ),
                                            (_shimmerAnimation.value + 0.3)
                                                .clamp(0.0, 1.0),
                                          ],
                                        ).createShader(bounds);
                                      },
                                      child: Container(
                                        width: 140,
                                        height: 140,
                                        color: Colors.white,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 50),

                      // ⭐ Texto con fade elegante
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: Column(
                          children: [
                            Text(
                              'GC',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.95),
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 3,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            ShaderMask(
                              shaderCallback: (bounds) {
                                return const LinearGradient(
                                  colors: [
                                    Color(0xFF6BA3E8),
                                    Color(0xFF4A90E2),
                                  ],
                                ).createShader(bounds);
                              },
                              child: const Text(
                                'SANIDAD',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ⭐ Painter para anillos sutiles de fondo
class SubtleRingsPainter extends CustomPainter {
  final double intensity;

  SubtleRingsPainter(this.intensity);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Dibujar 2 anillos sutiles
    for (int i = 0; i < 2; i++) {
      final radius = 200.0 + (i * 100) + (intensity * 30);
      final opacity = (0.08 + (intensity * 0.05)) * (1 - i * 0.3);

      final paint = Paint()
        ..color = const Color(0xFF6BA3E8).withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(SubtleRingsPainter oldDelegate) =>
      intensity != oldDelegate.intensity;
}

// ⭐ Barra de progreso minimalista
class _MinimalProgressBar extends StatefulWidget {
  @override
  State<_MinimalProgressBar> createState() => _MinimalProgressBarState();
}

class _MinimalProgressBarState extends State<_MinimalProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Column(
            children: [
              // Barra de fondo
              Stack(
                children: [
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                  // Barra de progreso
                  FractionallySizedBox(
                    widthFactor: _animation.value,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6BA3E8), Color(0xFF4A90E2)],
                        ),
                        borderRadius: BorderRadius.circular(1.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6BA3E8).withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Texto de carga (opcional)
              Text(
                'Cargando...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
