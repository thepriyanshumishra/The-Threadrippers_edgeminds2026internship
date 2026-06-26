// app/core/router/app_router.dart
// Purpose: Defines all navigation routes for Kivo Workspace.
// Responsibilities: Maps route paths to screen widgets. Keeps routing centralized.
// Inputs: None
// Outputs: GoRouter instance used by the root app widget.

import 'package:go_router/go_router.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/workspace/screens/workspace_screen.dart';
import '../../features/source_upload/screens/source_upload_screen.dart';
import '../../features/processing/screens/processing_screen.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/chat/screens/multi_workspace_chat_screen.dart';
import '../../features/processing/screens/system_health_screen.dart';
import '../../features/workspace/screens/workspace_settings_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/onboarding/screens/model_downloader_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String workspace = '/workspace/:workspaceId';
  static const String sourceUpload = '/workspace/:workspaceId/upload';
  static const String processing = '/workspace/:workspaceId/processing';
  static const String chat = '/workspace/:workspaceId/chat';
  static const String multiWorkspaceChat = '/multi-workspace-chat';
  static const String systemHealth = '/system-health';
  static const String workspaceSettings = '/workspace/:workspaceId/settings';
  static const String onboarding = '/onboarding';
  static const String modelDownloader = '/model-downloader';
}

final appRouter = GoRouter(
  initialLocation: AppRoutes.home,
  debugLogDiagnostics: false,
  routes: [
    GoRoute(
      path: AppRoutes.home,
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.workspace,
      name: 'workspace',
      builder: (context, state) {
        final workspaceId = state.pathParameters['workspaceId'] ?? '';
        return WorkspaceScreen(workspaceId: workspaceId);
      },
    ),
    GoRoute(
      path: AppRoutes.sourceUpload,
      name: 'sourceUpload',
      builder: (context, state) {
        final workspaceId = state.pathParameters['workspaceId'] ?? '';
        return SourceUploadScreen(workspaceId: workspaceId);
      },
    ),
    GoRoute(
      path: AppRoutes.processing,
      name: 'processing',
      builder: (context, state) {
        final workspaceId = state.pathParameters['workspaceId'] ?? '';
        return ProcessingScreen(workspaceId: workspaceId);
      },
    ),
    GoRoute(
      path: AppRoutes.chat,
      name: 'chat',
      builder: (context, state) {
        final workspaceId = state.pathParameters['workspaceId'] ?? '';
        return ChatScreen(workspaceId: workspaceId);
      },
    ),
    GoRoute(
      path: AppRoutes.multiWorkspaceChat,
      name: 'multiWorkspaceChat',
      builder: (context, state) => const MultiWorkspaceChatScreen(),
    ),
    GoRoute(
      path: AppRoutes.systemHealth,
      name: 'systemHealth',
      builder: (context, state) => const SystemHealthScreen(),
    ),
    GoRoute(
      path: AppRoutes.workspaceSettings,
      name: 'workspaceSettings',
      builder: (context, state) {
        final workspaceId = state.pathParameters['workspaceId'] ?? '';
        return WorkspaceSettingsScreen(workspaceId: workspaceId);
      },
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      name: 'onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: AppRoutes.modelDownloader,
      name: 'modelDownloader',
      builder: (context, state) => const ModelDownloaderScreen(),
    ),
  ],
);
