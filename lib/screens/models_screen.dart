import 'package:flutter/material.dart';
import '../models/app_state.dart';
import '../models/model_item.dart';

class ModelsScreen extends StatefulWidget {
  final AppState appState;

  const ModelsScreen({super.key, required this.appState});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  int _selectedTabIndex = 0; // 0 for LLM Models, 1 for Speech Models (Whisper)

  AppState get appState => widget.appState;

  String _getRecommendationStatus(ModelItem model, int deviceRam) {
    return appState.modelManager.getRecommendationStatus(model, deviceRam);
  }

  @override
  Widget build(BuildContext context) {
    if (appState.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF6366F1)),
            SizedBox(height: 16),
            Text(
              'Scanning device…',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
          ],
        ),
      );
    }

    final ram = appState.deviceRam;
    final storageGb = appState.freeStorageGb;
    final allModels = appState.models;

    // Segregate by family
    final llmModels = allModels
        .where((m) => m.modelFamily != 'Whisper')
        .toList();
    final speechModels = allModels
        .where((m) => m.modelFamily == 'Whisper')
        .toList();

    final currentModels = _selectedTabIndex == 0 ? llmModels : speechModels;

    final installedModels = currentModels
        .where((m) => m.status == 'installed')
        .toList();
    final downloadingModels = currentModels
        .where((m) => m.status == 'downloading')
        .toList();
    final availableModels = currentModels
        .where((m) => m.status == 'available')
        .toList();
    final recommendedModels = _selectedTabIndex == 0
        ? availableModels
              .where((m) => _getRecommendationStatus(m, ram) == 'recommended')
              .toList()
        : [];
    final otherAvailableModels = _selectedTabIndex == 0
        ? availableModels
              .where((m) => _getRecommendationStatus(m, ram) != 'recommended')
              .toList()
        : availableModels;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Download Error Banner
          if (appState.downloadErrorMessage.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFEF4444).withAlpha(60),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFEF4444),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Download failed: ${appState.downloadErrorMessage}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFFCA5A5),
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF94A3B8),
                      size: 14,
                    ),
                    onPressed: () => appState.clearDownloadError(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    splashRadius: 14,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Device Diagnostics
          _buildDiagnosticsPanel(context, ram, storageGb),
          const SizedBox(height: 20),

          // --- Segmented Tab Bar ---
          _buildSegmentedTabBar(),
          const SizedBox(height: 20),

          // Active Model Banner (LLM tab) or Active Whisper Banner (Speech tab)
          if (_selectedTabIndex == 0) ...[
            _buildActiveModelBanner(context),
            const SizedBox(height: 24),
          ] else ...[
            _buildActiveWhisperModelBanner(context),
            const SizedBox(height: 24),
          ],

          // Downloading
          if (downloadingModels.isNotEmpty) ...[
            _buildSectionHeader(
              'DOWNLOADING',
              Icons.download_rounded,
              const Color(0xFF6366F1),
            ),
            const SizedBox(height: 10),
            ...downloadingModels.map(
              (m) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildModelCard(context, m, ram),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Installed
          if (installedModels.isNotEmpty) ...[
            _buildSectionHeader(
              'INSTALLED ON DEVICE',
              Icons.memory_rounded,
              const Color(0xFF10B981),
            ),
            const SizedBox(height: 10),
            ...installedModels.map(
              (m) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildModelCard(context, m, ram),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Recommended (LLM only)
          if (recommendedModels.isNotEmpty) ...[
            _buildSectionHeader(
              'RECOMMENDED FOR YOUR DEVICE',
              Icons.star_rounded,
              const Color(0xFF10B981),
            ),
            const SizedBox(height: 10),
            ...recommendedModels.map(
              (m) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildModelCard(context, m, ram),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Other Available
          if (otherAvailableModels.isNotEmpty) ...[
            _buildSectionHeader(
              _selectedTabIndex == 0
                  ? 'AVAILABLE FOR DOWNLOAD'
                  : 'SPEECH MODELS — AVAILABLE',
              Icons.cloud_download_outlined,
              const Color(0xFF94A3B8),
            ),
            const SizedBox(height: 10),
            ...otherAvailableModels.map(
              (m) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildModelCard(context, m, ram),
              ),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // Segmented tab bar: LLM Models vs Speech Models
  Widget _buildSegmentedTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F19),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _buildTabItem(0, Icons.smart_toy_rounded, 'LLM Models'),
          _buildTabItem(1, Icons.mic_rounded, 'Speech Models'),
        ],
      ),
    );
  }

  Widget _buildTabItem(int index, IconData icon, String label) {
    final isActive = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF6366F1) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withAlpha(60),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isActive ? Colors.white : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isActive ? Colors.white : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  //  DIAGNOSTICS PANEL

  Widget _buildDiagnosticsPanel(
    BuildContext context,
    int ram,
    double storageGb,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF151E2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              const Icon(
                Icons.developer_board_rounded,
                color: Color(0xFF6366F1),
                size: 16,
              ),
              const SizedBox(width: 8),
              const Text(
                'Device Profile',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              // Live RAM badge
              _buildInfoBadge(
                icon: Icons.memory_rounded,
                label: '${ram}GB RAM',
                color: const Color(0xFF10B981),
              ),
              const SizedBox(width: 6),
              // Live Storage badge
              _buildInfoBadge(
                icon: Icons.storage_rounded,
                label: '${storageGb.toStringAsFixed(1)}GB free',
                color: const Color(0xFF6366F1),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Simulate RAM profile hint
          const Text(
            'Manually override RAM profile to preview recommendations:',
            style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildRamChip(context, 4, ram),
              const SizedBox(width: 8),
              _buildRamChip(context, 6, ram),
              const SizedBox(width: 8),
              _buildRamChip(context, 8, ram),
            ],
          ),
          const SizedBox(height: 10),

          // Badge legend
          Wrap(
            spacing: 12,
            children: [
              _buildBadgeLegend('✓ Recommended', const Color(0xFF10B981)),
              _buildBadgeLegend('⚠ May Be Slow', const Color(0xFFF59E0B)),
              _buildBadgeLegend('✕ Not Recommended', const Color(0xFFEF4444)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRamChip(BuildContext context, int value, int selected) {
    final isSelected = value == selected;
    return GestureDetector(
      onTap: () => appState.setDeviceRam(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF0B0F19),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6366F1)
                : const Color(0xFF1E293B),
          ),
        ),
        child: Text(
          '${value}GB',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }

  Widget _buildBadgeLegend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 8.5, color: color.withAlpha(200)),
        ),
      ],
    );
  }

  //  SECTION HEADER
  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  //  ACTIVE MODEL BANNER

  Widget _buildActiveModelBanner(BuildContext context) {
    final active = appState.activeModel;
    final loadState = appState.modelLoadState;

    if (active == null) {
      return _buildNoModelBanner();
    }

    // Show load-state on the banner
    Color stateColor;
    String stateLabel;
    IconData stateIcon;
    bool showSpinner = false;

    switch (loadState) {
      case ModelLoadState.loading:
        stateColor = const Color(0xFFF59E0B);
        stateLabel = 'Initialising…';
        stateIcon = Icons.hourglass_top_rounded;
        showSpinner = true;
        break;
      case ModelLoadState.loaded:
        stateColor = const Color(0xFF10B981);
        stateLabel = 'Ready';
        stateIcon = Icons.check_circle_rounded;
        break;
      case ModelLoadState.failed:
        stateColor = const Color(0xFFEF4444);
        stateLabel = 'Failed';
        stateIcon = Icons.error_outline_rounded;
        break;
      case ModelLoadState.unloaded:
        stateColor = const Color(0xFF94A3B8);
        stateLabel = 'Not Loaded';
        stateIcon = Icons.radio_button_unchecked_rounded;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: loadState == ModelLoadState.loaded
              ? [const Color(0xFF6366F1), const Color(0xFF4F46E5)]
              : [const Color(0xFF1E293B), const Color(0xFF151E2E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: loadState != ModelLoadState.loaded
            ? Border.all(color: stateColor.withAlpha(80))
            : null,
        boxShadow: loadState == ModelLoadState.loaded
            ? [
                BoxShadow(
                  color: const Color(0xFF6366F1).withAlpha(77),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: loadState == ModelLoadState.loaded
                      ? Colors.white.withAlpha(51)
                      : stateColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'ACTIVE MODEL',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              if (showSpinner)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFFF59E0B),
                    ),
                  ),
                )
              else
                Icon(stateIcon, color: stateColor, size: 14),
              const SizedBox(width: 5),
              Text(
                stateLabel,
                style: TextStyle(
                  fontSize: 10,
                  color: stateColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            active.fullName,
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: loadState == ModelLoadState.loaded
                  ? Colors.white
                  : Colors.white70,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _buildActiveMeta(
                Icons.memory,
                active.ram.replaceAll('Needs ', ''),
              ),
              const SizedBox(width: 10),
              _buildActiveMeta(Icons.storage_rounded, active.size),
              const SizedBox(width: 10),
              _buildActiveMeta(Icons.layers_rounded, active.quantization),
              const SizedBox(width: 10),
              _buildActiveMeta(
                Icons.wrap_text_rounded,
                '${active.contextWindow} ctx',
              ),
            ],
          ),
          if (loadState == ModelLoadState.failed) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFEF4444).withAlpha(60),
                ),
              ),
              child: Text(
                appState.modelStatusMessage,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFFEF4444),
                  height: 1.3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveWhisperModelBanner(BuildContext context) {
    final activeWhisper = appState.modelManager.activeWhisperModel;
    if (activeWhisper == null) {
      return _buildNoWhisperModelBanner();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF111827)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFF94A3B8).withAlpha(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF94A3B8).withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'ACTIVE SPEECH MODEL',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              Icon(Icons.mic_rounded, color: const Color(0xFF94A3B8), size: 14),
              const SizedBox(width: 5),
              const Text(
                'Ready',
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFF10B981),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            activeWhisper.fullName,
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _buildActiveMeta(
                Icons.memory_rounded,
                activeWhisper.ram.replaceAll('Needs ', ''),
              ),
              const SizedBox(width: 10),
              _buildActiveMeta(Icons.storage_rounded, activeWhisper.size),
              const SizedBox(width: 10),
              _buildActiveMeta(
                Icons.layers_rounded,
                activeWhisper.quantization,
              ),
              const SizedBox(width: 10),
              _buildActiveMeta(
                Icons.language_rounded,
                activeWhisper.modelFamily,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: _buildActionButton(
              label: 'Unload',
              icon: Icons.eject_rounded,
              color: const Color(0xFF94A3B8),
              outlined: true,
              onPressed: () => appState.unloadActiveWhisperModel(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoWhisperModelBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF151E2E),
        border: Border.all(color: const Color(0xFF94A3B8).withAlpha(40)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF94A3B8).withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.mic_off_rounded,
              color: Color(0xFF94A3B8),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No Active Speech Model',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Download and activate a Whisper model from the list below to enable speech recognition.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveMeta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: Colors.white54),
        const SizedBox(width: 3),
        Text(text, style: const TextStyle(fontSize: 10, color: Colors.white54)),
      ],
    );
  }

  Widget _buildNoModelBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF151E2E),
        border: Border.all(color: const Color(0xFFF59E0B).withAlpha(80)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFF59E0B),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No Active Model',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Download a model below, then tap Set Active to load it into memory.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  //  MODEL CARD

  Widget _buildModelCard(BuildContext context, ModelItem model, int ram) {
    final recStatus = _getRecommendationStatus(model, ram);
    final bool isInstalled = model.status == 'installed';
    final bool isDownloading = model.status == 'downloading';
    final bool isActiveModel = appState.activeModel?.id == model.id;
    final loadState = appState.modelLoadState;

    // Per-card load state label (only relevant for the active model)
    String? loadStateLabel;
    Color? loadStateColor;
    bool cardSpinner = false;
    if (isActiveModel && isInstalled) {
      switch (loadState) {
        case ModelLoadState.loading:
          loadStateLabel = 'Loading…';
          loadStateColor = const Color(0xFFF59E0B);
          cardSpinner = true;
          break;
        case ModelLoadState.loaded:
          loadStateLabel = 'In Memory';
          loadStateColor = const Color(0xFF10B981);
          break;
        case ModelLoadState.failed:
          loadStateLabel = 'Load Failed';
          loadStateColor = const Color(0xFFEF4444);
          break;
        case ModelLoadState.unloaded:
          loadStateLabel = 'Not Loaded';
          loadStateColor = const Color(0xFF94A3B8);
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF151E2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: model.active
              ? const Color(0xFF6366F1)
              : const Color(0xFF1E293B),
          width: model.active ? 1.5 : 1,
        ),
        boxShadow: model.active
            ? [
                BoxShadow(
                  color: const Color(0xFF6366F1).withAlpha(30),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _categoryColor(model.category).withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _categoryIcon(model.category),
                  color: _categoryColor(model.category),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              // Name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.fullName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      model.category,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Status badges
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (model.active)
                    _buildBadge('ACTIVE', const Color(0xFF10B981)),
                  if (isInstalled && !model.active)
                    _buildBadge('INSTALLED', const Color(0xFF6366F1)),
                  if (!isInstalled && !isDownloading) _buildRecBadge(recStatus),
                  if (loadStateLabel != null) ...[
                    const SizedBox(height: 4),
                    _buildLoadStateBadge(
                      loadStateLabel,
                      loadStateColor!,
                      cardSpinner,
                    ),
                  ],
                ],
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Metadata chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildMetaChip(Icons.storage_rounded, model.size),
              _buildMetaChip(
                Icons.memory_rounded,
                model.ram.replaceAll('Needs ', ''),
              ),
              _buildMetaChip(Icons.layers_rounded, model.quantization),
              _buildMetaChip(
                Icons.wrap_text_rounded,
                '${model.contextWindow} ctx',
              ),
              _buildMetaChip(Icons.category_rounded, model.modelFamily),
            ],
          ),

          // Download progress
          if (isDownloading) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Downloading…',
                  style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                ),
                Text(
                  '${(model.downloadProgress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF6366F1),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: model.downloadProgress,
                backgroundColor: const Color(0xFF1E293B),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF6366F1),
                ),
                minHeight: 5,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => appState.cancelDownload(model),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF94A3B8),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],

          // Action buttons
          if (!isDownloading) ...[
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF1E293B), height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isInstalled) ...[
                  // Set Active / Unload / Reload
                  if (!model.active ||
                      loadState == ModelLoadState.unloaded ||
                      loadState == ModelLoadState.failed)
                    _buildActionButton(
                      label: loadState == ModelLoadState.failed && isActiveModel
                          ? 'Retry Load'
                          : 'Set Active',
                      icon: Icons.play_circle_outline_rounded,
                      color: loadState == ModelLoadState.failed && isActiveModel
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF6366F1),
                      enabled: loadState != ModelLoadState.loading,
                      onPressed: () {
                        if (_selectedTabIndex == 1) {
                          // Speech tab: activate via WhisperSttService, NOT llama_cpp_dart
                          debugPrint(
                            '[ModelsScreen] Activating Whisper model: ${model.id} '
                            '(path: ${model.localPath}) → selectWhisperModel()',
                          );
                          appState.selectWhisperModel(model);
                        } else {
                          // LLM tab: activate via LocalLlmService
                          debugPrint(
                            '[ModelsScreen] Activating LLM model: ${model.id} '
                            '(path: ${model.localPath}) → selectModel()',
                          );
                          appState.selectModel(model);
                        }
                      },
                    ),
                  if (model.active && loadState == ModelLoadState.loaded) ...[
                    _buildActionButton(
                      label: 'Unload',
                      icon: Icons.eject_rounded,
                      color: const Color(0xFF94A3B8),
                      outlined: true,
                      onPressed: () => appState.unloadActiveModel(),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (model.active) const SizedBox(width: 8),
                  _buildActionButton(
                    label: 'Delete',
                    icon: Icons.delete_outline_rounded,
                    color: const Color(0xFFEF4444),
                    outlined: true,
                    enabled: loadState != ModelLoadState.loading,
                    onPressed: () => _confirmDelete(context, model),
                  ),
                ] else ...[
                  _buildActionButton(
                    label: 'Download',
                    icon: Icons.download_rounded,
                    color: const Color(0xFF6366F1),
                    onPressed: () => appState.downloadModel(model),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  //  BADGE HELPERS

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildLoadStateBadge(String label, Color color, bool spinner) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spinner)
            SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(
                strokeWidth: 1.2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          else
            Icon(Icons.circle, size: 5, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecBadge(String recStatus) {
    switch (recStatus) {
      case 'recommended':
        return _buildBadge('✓ Recommended', const Color(0xFF10B981));
      case 'slow':
        return _buildBadge('⚠ May Be Slow', const Color(0xFFF59E0B));
      case 'not_recommended':
        return _buildBadge('✕ Not Recommended', const Color(0xFFEF4444));
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildMetaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F19),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    bool outlined = false,
    bool enabled = true,
  }) {
    final effectiveColor = enabled ? color : const Color(0xFF334155);
    if (outlined) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: effectiveColor,
          side: BorderSide(color: effectiveColor.withAlpha(80)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 13),
        label: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
      );
    }
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: effectiveColor,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 13),
      label: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  //  CATEGORY HELPERS

  Color _categoryColor(String category) {
    switch (category) {
      case 'General Text':
        return const Color(0xFF6366F1);
      case 'Reasoning':
        return const Color(0xFF10B981);
      case 'Advanced Text':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF94A3B8);
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'General Text':
        return Icons.chat_bubble_outline_rounded;
      case 'Reasoning':
        return Icons.psychology_rounded;
      case 'Advanced Text':
        return Icons.auto_awesome_rounded;
      default:
        return Icons.memory_rounded;
    }
  }

  //  DELETE DIALOG
  void _confirmDelete(BuildContext context, ModelItem model) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Model',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        content: Text(
          'This will permanently delete "${model.fullName}" (${model.size}) from your device storage.',
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF94A3B8),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              appState.deleteModel(model);
            },
            child: const Text(
              'Delete',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
