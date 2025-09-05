import 'package:flutter/material.dart';
import 'package:shnell/dots.dart';

class Waiting extends StatefulWidget {
  const Waiting({super.key});

  @override
  State<Waiting> createState() => _WaitingState();
}

class _WaitingState extends State<Waiting> with TickerProviderStateMixin {
  final String fullText = "rapide, fiable et sécurisée";
  late AnimationController _controller;
  late Animation<int> _textAnimation;
  bool showFinalText = false;

  @override
  void initState() {
    super.initState();

    // Initialize AnimationController
    _controller = AnimationController(
      duration: Duration(milliseconds: fullText.length *35),
      vsync: this,
    );

    // Define the text animation
    _textAnimation = IntTween(begin: 0, end: fullText.length).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    )..addListener(() {
        setState(() {});
      });

    // Start the animation
    _controller.forward();

    // Show final text after animation completes
    Future.delayed(_controller.duration!, () {
      setState(() {
        showFinalText = true;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: showFinalText
                  ? Image.asset(
                      'assets/shnell.jpeg',
                      width: 150,
                      height: 150,
                      color: Colors.amber,
                      colorBlendMode: BlendMode.modulate,
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/box.png',
                          width: 50,
                          height: 50,
                          color: Colors.amber,
                          colorBlendMode: BlendMode.modulate,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Shnell',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 40,
                            color: Colors.amber,
                          ),
                        ),
                      ],
                    ),
            ),
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Center(
                child: showFinalText
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Make sure you are online",
                            style: TextStyle(color: Colors.white, fontSize: 18),
                          ),
                          SizedBox(width: 12),
                          RotatingDotsIndicator(),
                        ],
                      )
                    : Text(
                        fullText.substring(0, _textAnimation.value),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
