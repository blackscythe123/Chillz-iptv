import 'package:flutter/material.dart';
import 'dart:io';
// import 'package:url_launcher/url_launcher.dart';
import '../main.dart'; // Import for ChillzHome

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Force a dark theme for the landing page or inherit from app
    return Scaffold(
      backgroundColor: const Color(0xFF0F1720), // Deep blue/black background
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: 1200), // Max width for content
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 100),
                  _buildAboutDeveloper(),
                  const SizedBox(height: 20),
                  Center(
                      child: _buildStartWatchingButton(
                          context)), // Second "Start Watching" button
                  const SizedBox(height: 100),
                  _buildHowItWorks(),
                  const SizedBox(height: 100),
                  _buildImportantNotes(),
                  const SizedBox(height: 100),
                  _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      children: [
        // Decorative graphic hint (simplified for code)
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Colors.cyan.shade400, Colors.blue.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.cyan.withOpacity(0.4),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: const Icon(Icons.play_arrow_rounded,
              color: Colors.white, size: 50),
        ),
        const SizedBox(height: 30),
        const Text(
          'Chillz TV',
          style: TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Cross-platform IPTV player built for unstable streams',
          style: TextStyle(
            fontSize: 24,
            color: Colors.grey[400],
            letterSpacing: 0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 60),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildStartWatchingButton(context),
            const SizedBox(width: 24),
            _buildOutlinedButton(
              icon: Icons
                  .code, // Placeholder for GitHub icon if generic isn't preferred
              label: 'View on GitHub',
              onPressed: () =>
                  _launchUrl('https://github.com/blackscythe123/Chillz-iptv'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStartWatchingButton(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ChillzHome()),
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.cyan.shade600,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 10,
        shadowColor: Colors.cyan.withOpacity(0.4),
        textStyle: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.0),
      ),
      child: const Text('Start Watching'),
    );
  }

  Widget _buildOutlinedButton(
      {required IconData icon,
      required String label,
      required VoidCallback onPressed}) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.grey.shade700, width: 2),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      icon: Icon(icon, size: 24),
      label: Text(label),
    );
  }

  Widget _buildAboutDeveloper() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border:
                    Border.all(color: Colors.cyan.withOpacity(0.5), width: 2),
                boxShadow: [
                  BoxShadow(
                      color: Colors.cyan.withOpacity(0.2), blurRadius: 15),
                ],
              ),
              child: const CircleAvatar(
                radius: 60,
                backgroundImage: AssetImage('assets/images/profile.png'),
                backgroundColor: Colors.grey, // Fallback
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Simiyon Vinscent Samuel L',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              '@blackscythe123',
              style: TextStyle(fontSize: 18, color: Colors.cyan.shade400),
            ),
            const SizedBox(height: 16),
            Text(
              'Student developer & creator of Chillz TV. Built to make broken IPTV streams playable using native engines (libVLC, MPV). No tracking. No accounts.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 18, color: Colors.grey[300], height: 1.5),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => _launchUrl('https://simiyonvinscentsamuel.tech'),
              child: Text(
                'simiyonvinscentsamuel.tech',
                style: TextStyle(color: Colors.cyan.shade300, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHowItWorks() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How it Works',
          style: TextStyle(
              fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 40),
        Row(
          children: [
            Expanded(
                child: _buildInfoCard(Icons.window, 'Windows',
                    'Native libVLC integration for robust playback')),
            const SizedBox(width: 24),
            Expanded(
                child: _buildInfoCard(Icons.android, 'Android / TV',
                    'MPV backend for native playback')),
            const SizedBox(width: 24),
            Expanded(
                child: _buildInfoCard(
                    Icons.web, 'Web', 'HLS.js lightweight player')),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoCard(IconData icon, String title, String description) {
    return Container(
      padding: const EdgeInsets.all(32),
      height: 220,
      decoration: BoxDecoration(
        color: const Color(0xFF1A222C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 40, color: Colors.cyan.shade400),
          const Spacer(),
          Text(title,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 12),
          Text(description,
              style: TextStyle(
                  fontSize: 16, color: Colors.grey[400], height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildImportantNotes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Important Notes',
          style: TextStyle(
              fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 40),
        Wrap(
          spacing: 24,
          runSpacing: 24,
          children: [
            _buildNoteBox(
                'Geo-blocked streams? Use VPN for the channel’s country.'),
            _buildNoteBox(
                'College/office Wi-Fi may block streams — try mobile hotspot or VPN.'),
            _buildNoteBox('These are public streams — availability varies.'),
          ],
        ),
      ],
    );
  }

  Widget _buildNoteBox(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 16, color: Colors.grey[300]),
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Divider(color: Colors.grey.shade800),
        const SizedBox(height: 40),
        Text(
          'Built with Flutter • libVLC • MPV • HLS.js',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () =>
              _launchUrl('https://github.com/blackscythe123/Chillz-iptv'),
          child: Text(
            'https://github.com/blackscythe123/Chillz-iptv',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Future<void> _launchUrl(String url) async {
    try {
      debugPrint('Launching URL: $url');
      // Windows-specific URL launcher using system shell
      await Process.run('start', [url], runInShell: true);
    } catch (e) {
      debugPrint('Could not launch $url: $e');
    }
  }
}
