import 'package:flutter/material.dart';

void main() {
  runApp(const CapsiWebsite());
}

class CapsiWebsite extends StatelessWidget {
  const CapsiWebsite({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Capsi — Messages and files, device to device.',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF090B0C),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB8F36B),
          brightness: Brightness.dark,
        ),
      ),
      home: const CapsiLanding(),
    );
  }
}

class CapsiLanding extends StatelessWidget {
  const CapsiLanding({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SelectionArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: const Color(0xFF090B0C),
              surfaceTintColor: Colors.transparent,
              title: const _Brand(),
              actions: [
                TextButton(
                  onPressed: () => _scroll(context, 'how'),
                  child: const Text('How it works'),
                ),
                TextButton(
                  onPressed: () => _scroll(context, 'features'),
                  child: const Text('Features'),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: FilledButton(
                    onPressed: () {},
                    child: const Text('Download'),
                  ),
                ),
              ],
            ),
            SliverToBoxAdapter(child: _Hero()),
            SliverToBoxAdapter(child: _Principle()),
            SliverToBoxAdapter(child: _HowItWorks()),
            SliverToBoxAdapter(child: _Features()),
            SliverToBoxAdapter(child: _LocalFirst()),
            SliverToBoxAdapter(child: _Download()),
            SliverToBoxAdapter(child: _Footer()),
          ],
        ),
      ),
    );
  }

  void _scroll(BuildContext context, String id) {
    // The landing page is intentionally simple for the first Flutter web pass.
    // Navigation will be wired to section keys when routing is introduced.
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: const Text(
            'C',
            style: TextStyle(
              color: Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'CAPSI',
          style: TextStyle(
            letterSpacing: 1.8,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 680),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 96),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Wrap(
            spacing: 72,
            runSpacing: 56,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 540,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CAPSI',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            letterSpacing: 3,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Run it. Find devices. Send.',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                          ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Messages and files, device to device.',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Capsi lets connected devices discover each other and communicate directly. No cloud service. No accounts. No unnecessary infrastructure.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Colors.white70,
                            height: 1.65,
                          ),
                    ),
                    const SizedBox(height: 28),
                    const Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _Fact('Device to device'),
                        _Fact('No account'),
                        _Fact('No internet required'),
                      ],
                    ),
                    const SizedBox(height: 34),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Download Capsi'),
                        ),
                        OutlinedButton(
                          onPressed: () {},
                          child: const Text('See how it works'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Windows (64-bit) · Free to download and use',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white54,
                          ),
                    ),
                  ],
                ),
              ),
              const _AppPreview(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final String text;
  const _Fact(this.text);

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        Icons.check,
        size: 15,
        color: Theme.of(context).colorScheme.primary,
      ),
      label: Text(text),
    );
  }
}

class _AppPreview extends StatelessWidget {
  const _AppPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 480,
      height: 330,
      decoration: BoxDecoration(
        color: const Color(0xFF111516),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
        boxShadow: const [
          BoxShadow(
            blurRadius: 50,
            spreadRadius: -20,
            offset: Offset(0, 25),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: const Row(
              children: [
                Icon(Icons.circle, size: 9),
                SizedBox(width: 8),
                Text('Capsi'),
                Spacer(),
                Icon(Icons.more_horiz, size: 18),
              ],
            ),
          ),
          const Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 132,
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Nearby'),
                        SizedBox(height: 18),
                        _PreviewDevice('Office PC'),
                        _PreviewDevice('Laptop'),
                      ],
                    ),
                  ),
                ),
                VerticalDivider(width: 1),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.devices_outlined, size: 42),
                        SizedBox(height: 12),
                        Text('Find devices. Send.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewDevice extends StatelessWidget {
  final String name;
  const _PreviewDevice(this.name);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        name,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String body;
  const _Section({
    required this.eyebrow,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 100),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Wrap(
            spacing: 80,
            runSpacing: 28,
            children: [
              SizedBox(
                width: 460,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            letterSpacing: 2.5,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w750,
                            height: 1.15,
                          ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 500,
                child: Text(
                  body,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white70,
                        height: 1.75,
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

class _Principle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const _Section(
      eyebrow: 'THE IDEA',
      title: 'Communication does not always need a middleman.',
      body:
          'Capsi is built around a simple idea: when your devices can reach each other, they should be able to talk to each other. Your setup can be Wi-Fi, wired Ethernet, a hotspot, or another connected local network.',
    );
  }
}

class _HowItWorks extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0E1112),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 100),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SIMPLE BY DESIGN',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        letterSpacing: 2.5,
                        color: Theme.of(context).colorScheme.primary,
                      )),
              const SizedBox(height: 14),
              Text('How it works',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      )),
              const SizedBox(height: 42),
              const Wrap(
                spacing: 18,
                runSpacing: 18,
                children: [
                  _Step('01', 'Run', 'Install Capsi and give your device a name.'),
                  _Step('02', 'Find', 'Capsi discovers other Capsi devices nearby.'),
                  _Step('03', 'Send', 'Accept a device, then send messages and files.'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String number;
  final String title;
  final String body;
  const _Step(this.number, this.title, this.body);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 350,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(number, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 28),
              Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  )),
              const SizedBox(height: 10),
              Text(body, style: const TextStyle(color: Colors.white70, height: 1.6)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Features extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const features = [
      ('Device Discovery', Icons.devices_outlined, 'See nearby Capsi devices without typing addresses.'),
      ('Direct Messages', Icons.chat_bubble_outline, 'Send one-to-one messages between accepted devices.'),
      ('File Transfer', Icons.insert_drive_file_outlined, 'Offer files directly to another trusted device.'),
      ('Device Trust', Icons.verified_user_outlined, 'New devices wait for you to accept them.'),
      ('No Cloud', Icons.cloud_off_outlined, 'Local conversations and transfers do not need a Capsi cloud.'),
      ('No Account', Icons.person_off_outlined, 'No signup or login. Your device identity is local.'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 100),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('WHAT YOU GET',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        letterSpacing: 2.5,
                        color: Theme.of(context).colorScheme.primary,
                      )),
              const SizedBox(height: 14),
              Text('The useful parts. Nothing extra.',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      )),
              const SizedBox(height: 38),
              Wrap(
                spacing: 18,
                runSpacing: 18,
                children: [
                  for (final feature in features)
                    SizedBox(
                      width: 350,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(feature.$2),
                              const SizedBox(height: 24),
                              Text(feature.$1,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      )),
                              const SizedBox(height: 8),
                              Text(feature.$3,
                                  style: const TextStyle(color: Colors.white70, height: 1.55)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalFirst extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0E1112),
      child: const _Section(
        eyebrow: 'LOCAL FIRST',
        title: 'Your devices. Your network. Your data.',
        body:
            'Capsi does not need an external chat service to move messages and files between connected devices. No cloud account, no login, no internet connection required for local communication, and conversation history stays on the device.',
      ),
    );
  }
}

class _Download extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 120),
      child: Center(
        child: Column(
          children: [
            Text('CAPSI',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      letterSpacing: 3,
                      color: Theme.of(context).colorScheme.primary,
                    )),
            const SizedBox(height: 14),
            Text('Ready to connect?',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    )),
            const SizedBox(height: 12),
            const Text(
              'Run Capsi on your computers. Find each other. Send messages and files.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () {},
              icon: Icon(Icons.download_outlined),
              label: Text('Download Capsi'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(28, 32, 28, 44),
      child: Center(
        child: Text(
          'CAPSI · Messages and files, device to device.',
          style: TextStyle(color: Colors.white54),
        ),
      ),
    );
  }
}
