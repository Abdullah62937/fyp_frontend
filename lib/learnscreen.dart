import 'package:flutter/material.dart';
import '../main.dart';

class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key});

  // Demo signs + simple how-to (apne dataset ke words ke hisaab se edit karo)
  static const List<Map<String, String>> signs = [
  {'word': 'Hello', 'how': 'Hold your flat hand near your forehead and move it outward (like a salute).', 'icon': '👋'},
  {'word': 'Thank you', 'how': 'Touch your chin or lips with your fingertips, then move your hand forward and down.', 'icon': '🙏'},
  {'word': 'Please', 'how': 'Place your flat hand on your chest and move it in a circular motion.', 'icon': '🤲'},
  {'word': 'Yes', 'how': 'Make a fist and bob it up and down (like nodding your head).', 'icon': '✊'},
  {'word': 'No', 'how': 'Bring your index and middle fingers together with your thumb.', 'icon': '✌️'},
  {'word': 'Help', 'how': 'Place one fist (thumb up) on your other open palm and lift both hands upward.', 'icon': '🤝'},
  {'word': 'Sorry', 'how': 'Place your fist on your chest and move it in a circular motion.', 'icon': '😔'},
  {'word': 'I love you', 'how': 'Extend your thumb, index finger, and pinky finger with your palm facing forward.', 'icon': '🤟'},
];

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _appBar(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                    'Perform these signs in front of the camera. (You can also watch "ASL sign for hello" on YouTube.)',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 13,
                        height: 1.4)),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  itemCount: signs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _signCard(signs[i]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _appBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          const Text('Learn Signs',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _signCard(Map<String, String> s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                  colors: [AppColors.accent, AppColors.accent2]),
            ),
            child: Text(s['icon'] ?? '🤚',
                style: const TextStyle(fontSize: 26)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s['word'] ?? '',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(s['how'] ?? '',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.65),
                        fontSize: 13,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}