import 'package:flutter/material.dart';
import '../main.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  // 👉 Apne team members yahan edit karo
  static const List<Map<String, String>> team = [
    {'name': 'Abdullah Faisal', 'roll': 'SE221070'},
    {'name': 'Muaz Ilyas', 'roll': 'SE221072'},
    {'name': 'Hamza Tariq', 'roll': 'SE221078'},
    {'name': 'Fasih Ur Rehman', 'roll': 'SE221067'},
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                    ),
                    const Text('About',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),

                // project card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                        colors: [AppColors.accent, AppColors.accent2]),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.sign_language_rounded,
                          color: Colors.white, size: 36),
                      SizedBox(height: 12),
                      Text('Real-Time Gesture to Voice',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text(
                          'This app recognizes sign language gestures through the camera and converts them into voice in real time.',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              height: 1.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                _sectionTitle('Supervisor'),
                const SizedBox(height: 10),
                _infoRow(Icons.person_outline_rounded, 'Miss Yusra Shahina',
                    'Project Supervisor'),
                const SizedBox(height: 22),

                _sectionTitle('Team Members'),
                const SizedBox(height: 10),
                ...team.map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _infoRow(Icons.account_circle_outlined,
                          m['name'] ?? '', m['roll'] ?? ''),
                    )),
                const SizedBox(height: 18),

                _sectionTitle('Institute'),
                const SizedBox(height: 10),
                _infoRow(Icons.school_outlined, 'DHA Suffa University',
                    'Software Engineering • FYP 2026'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t.toUpperCase(),
      style: TextStyle(
          color: Colors.white.withOpacity(0.5),
          fontSize: 12,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w600));

  Widget _infoRow(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.55), fontSize: 12.5)),
            ],
          ),
        ],
      ),
    );
  }
}