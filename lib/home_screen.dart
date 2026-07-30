import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fyp/MI%20Placeholder.dart';
import 'package:fyp/aboutscreen.dart';
import 'package:fyp/learnscreen.dart';
import '../main.dart';
import 'camera_screen.dart';
import 'word_to_sentence_screen.dart';
import 'package:fyp/api_service.dart';
import 'package:fyp/word_api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();

    // Let the first HomeScreen frame render before starting expensive ML
    // initialisation. This removes the visible startup freeze while still
    // preloading both models and waking both prediction backends early.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ApiService.warmUp();
      WordApiService.warmUp();
      MlPreloader.preload().catchError((error) {
        debugPrint('Background ML preload failed: $error');
      });
    });

    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulse = Tween(begin: 0.97, end: 1.03)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _go(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.bg1, AppColors.bg2, AppColors.bg1],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // ✅ FIX: Blobs ko RepaintBoundary mein wrap karo
              // Yeh unhe main tree se alag rakhe ga — animation ke waqt rebuild nahi honge
              Positioned(
                top: -70,
                right: -50,
                child: RepaintBoundary(
                  child: _blob(AppColors.accent.withOpacity(0.30), 230),
                ),
              ),
              Positioned(
                bottom: -60,
                left: -60,
                child: RepaintBoundary(
                  child: _blob(AppColors.accent2.withOpacity(0.25), 250),
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 44,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _header(),
                            const SizedBox(height: 24),
                            _titleBlock(),
                            const SizedBox(height: 20),
                            _sectionLabel('CHOOSE A MODE'),
                            const SizedBox(height: 30),
                            _modeCta(
                              icon: Icons.videocam_rounded,
                              title: 'Alphabet to Word',
                              subtitle: 'Fingerspell letters and build a word',
                              colors: const [AppColors.accent, AppColors.accent2],
                              onTap: () => _go(const CameraScreen()),
                            ),
                            const SizedBox(height: 14),
                            _modeCta(
                              icon: Icons.record_voice_over_rounded,
                              title: 'Word to Sentence',
                              subtitle: 'Sign full words and build a sentence',
                              colors: const [AppColors.accent2, Color(0xFF26C6DA)],
                              onTap: () => _go(const WordToSentenceScreen()),
                            ),
                            const SizedBox(height: 20),
                            const Spacer(),
                            Row(
                              children: [
                                Expanded(
                                  child: _featureCard(
                                    icon: Icons.menu_book_rounded,
                                    title: 'Learn Signs',
                                    subtitle: 'Sign guide',
                                    colors: const [
                                      Color(0xFF26C6DA),
                                      Color(0xFF2E7DF6),
                                    ],
                                    onTap: () => _go(const LearnScreen()),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _featureCard(
                                    icon: Icons.info_outline_rounded,
                                    title: 'About',
                                    subtitle: 'Project & team',
                                    colors: const [
                                      Color(0xFFAB47BC),
                                      Color(0xFF7C4DFF),
                                    ],
                                    onTap: () => _go(const AboutScreen()),
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 26),
                            _footer(),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [AppColors.accent, AppColors.accent2],
            ),
          ),
          child: const Icon(Icons.sign_language_rounded,
              color: Colors.white, size: 26),
        ),
        const SizedBox(width: 12),
        const Text('GestureVoice',
            style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold)),
        const Spacer(),
        _glassPill(
          child: const Text('FYP 2026',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
        ),
      ],
    );
  }

  Widget _titleBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Sign Language\nto Voice',
            style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                height: 1.15,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'Convert hand gestures into text and voice in real time.',
          style: TextStyle(
              color: Colors.white.withOpacity(0.65),
              fontSize: 14.5,
              height: 1.4),
        ),
      ],
    );
  }



  Widget _stat(String value, String label) {
    // ✅ FIX: BackdropFilter HATA DIYA — yeh stats box sirf static info dikh raha tha
    // BackdropFilter ek expensive GPU operation hai, har frame blur karta tha
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.55), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: TextStyle(
          color: Colors.white.withOpacity(0.45),
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      );

  Widget _modeCta({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return ScaleTransition(
      scale: _pulse,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.first.withOpacity(0.45),
                blurRadius: 26,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style:
                            const TextStyle(color: Colors.white70, fontSize: 12.5)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _featureCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 130,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: AppColors.glass,
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(colors: colors),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const Spacer(),
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.55), fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    return Center(
      child: Column(
        children: [
          Text('DHA Suffa University',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text('Final Year Project • 2026',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.35), fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _blob(Color c, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [c, c.withOpacity(0)]),
        ),
      );

  Widget _glassPill({required Widget child}) => ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.glass,
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: child,
          ),
        ),
      );
}