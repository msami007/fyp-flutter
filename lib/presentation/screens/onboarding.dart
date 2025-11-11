import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../routes/app_routes.dart';

// ============================================
// ONBOARDING PAGE
// File: onboarding_page.dart
// ============================================

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({Key? key}) : super(key: key);

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late AnimationController _iconAnimationController;
  late AnimationController _fadeAnimationController;

  final List<OnboardingSlide> _slides = [
    OnboardingSlide(
      title: 'Welcome to\nHearWise',
      description:
      'Experience crystal-clear sound with our advanced hearing solution designed for your comfort and clarity.',
      icon: Icons.hearing_rounded,
      gradient: const [
        Color(0xFF0A0E27), // Dark blue background
        Color(0xFF1E2139), // Lighter dark blue
      ],
      accentColor: const Color(0xFF6C63FF),
    ),
    OnboardingSlide(
      title: 'Personalized\nSound Profile',
      description:
      'AI-powered technology that adapts to your unique hearing needs and preferences in real-time.',
      icon: Icons.graphic_eq_rounded,
      gradient: const [
        Color(0xFF0A0E27),
        Color(0xFF1E2139),
      ],
      accentColor: const Color(0xFF6C63FF),
    ),
    OnboardingSlide(
      title: 'Seamless\nConnectivity',
      description:
      'Connect effortlessly with all your devices. Control everything from your smartphone with precision.',
      icon: Icons.settings_input_antenna_rounded,
      gradient: const [
        Color(0xFF0A0E27),
        Color(0xFF1E2139),
      ],
      accentColor: const Color(0xFF6C63FF),
    ),
    OnboardingSlide(
      title: 'Begin Your\nJourney',
      description:
      'Join thousands who have rediscovered the joy of hearing. Your personalized experience starts now.',
      icon: Icons.stars_rounded,
      gradient: const [
        Color(0xFF0A0E27),
        Color(0xFF1E2139),
      ],
      accentColor: const Color(0xFF6C63FF),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _iconAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _fadeAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _fadeAnimationController.reset();
      _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
      _fadeAnimationController.forward();
    } else {
      _finishOnboarding();
    }
  }

  void _skipToEnd() {
    _pageController.animateToPage(
      _slides.length - 1,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOutCubic,
    );
  }

  void _finishOnboarding() {
    // Create a custom top banner
    _showTopWelcomeBanner();

    // Smooth transition to login
    Future.delayed(const Duration(milliseconds: 1500), () {
      Navigator.pushReplacementNamed(context, AppRoutes.login);
    });
  }

  void _showTopWelcomeBanner() {
    // Create an overlay entry for top positioning
    OverlayEntry? overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 40, // Displaced 40px down to avoid camera cutout
        left: 0,
        right: 0,
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.all(0),
            child: Dismissible(
              key: UniqueKey(),
              direction: DismissDirection.up,
              onDismissed: (_) {
                overlayEntry?.remove();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E2139), Color(0xFF0A0E27)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: const Color(0xFF6C63FF).withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Animated icon with bounce
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 600),
                      tween: Tween(begin: 0.0, end: 1.0),
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: value,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6C63FF), Color(0xFF4A44B5)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6C63FF).withOpacity(0.4),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.celebration_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Welcome to HearWise! 🎉',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Your hearing journey begins now',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Insert the overlay
    Overlay.of(context).insert(overlayEntry);

    // Auto remove after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      overlayEntry?.remove();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _iconAnimationController.dispose();
    _fadeAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      body: Stack(
        children: [
          // Animated background with dark gradients
          AnimatedBuilder(
            animation: _pageController,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _slides[_currentPage].gradient,
                    stops: const [0.3, 0.7],
                  ),
                ),
              );
            },
          ),

          // Decorative circles with purple glow
          _buildDecorativeElements(),

          // Content
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
              _fadeAnimationController.reset();
              _fadeAnimationController.forward();
            },
            itemCount: _slides.length,
            itemBuilder: (context, index) {
              return FadeTransition(
                opacity: _fadeAnimationController,
                child: _SlideContent(
                  slide: _slides[index],
                  animationController: _iconAnimationController,
                ),
              );
            },
          ),

          // Skip button
          if (_currentPage < _slides.length - 1)
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Material(
                    color: const Color(0xFF6C63FF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(30),
                    child: InkWell(
                      onTap: _skipToEnd,
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        child: const Text(
                          'Skip',
                          style: TextStyle(
                            color: Color(0xFF6C63FF),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    // Page indicators with animation
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _slides.length,
                            (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          height: 4,
                          width: _currentPage == index ? 32 : 4,
                          decoration: BoxDecoration(
                            color: _currentPage == index
                                ? const Color(0xFF6C63FF)
                                : const Color(0xFF6C63FF).withOpacity(0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Next/Get Started button
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _nextPage,
                        borderRadius: BorderRadius.circular(50),
                        child: Container(
                          width: double.infinity,
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF6C63FF),
                                Color(0xFF5A52D5),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(50),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6C63FF).withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _currentPage < _slides.length - 1
                                    ? 'Continue'
                                    : 'Get Started',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDecorativeElements() {
    return Stack(
      children: [
        Positioned(
          top: -100,
          right: -100,
          child: AnimatedBuilder(
            animation: _iconAnimationController,
            builder: (context, child) {
              return Transform.scale(
                scale: 1 + (_iconAnimationController.value * 0.1),
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF6C63FF).withOpacity(0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(
          bottom: -50,
          left: -50,
          child: AnimatedBuilder(
            animation: _iconAnimationController,
            builder: (context, child) {
              return Transform.scale(
                scale: 1 + ((1 - _iconAnimationController.value) * 0.1),
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF6C63FF).withOpacity(0.06),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ============================================
// SLIDE CONTENT WIDGET
// ============================================

class _SlideContent extends StatelessWidget {
  final OnboardingSlide slide;
  final AnimationController animationController;

  const _SlideContent({
    required this.slide,
    required this.animationController,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
        child: Column(
          children: [
            const Spacer(),

            // Animated icon with glow effect
            AnimatedBuilder(
              animation: animationController,
              builder: (context, child) {
                final scale = 1 + (animationController.value * 0.15);
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: slide.accentColor.withOpacity(0.1),
                      boxShadow: [
                        BoxShadow(
                          color: slide.accentColor.withOpacity(0.3),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        slide.icon,
                        size: 70,
                        color: slide.accentColor,
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 60),

            // Title with white text
            Text(
              slide.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.1,
                letterSpacing: -0.5,
              ),
            ),

            const SizedBox(height: 24),

            // Description with light gray text
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                slide.description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  color: Colors.white.withOpacity(0.8),
                  height: 1.6,
                  letterSpacing: 0.3,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),

            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}

// ============================================
// ONBOARDING SLIDE MODEL
// ============================================

class OnboardingSlide {
  final String title;
  final String description;
  final IconData icon;
  final List<Color> gradient;
  final Color accentColor;

  OnboardingSlide({
    required this.title,
    required this.description,
    required this.icon,
    required this.gradient,
    required this.accentColor,
  });
}