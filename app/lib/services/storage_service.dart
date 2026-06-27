import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'package:swap/models/profile.dart';
import 'package:flutter/foundation.dart';

import '../models/swap_history.dart';

class StorageService {
  static const String fileName = 'profiles.json';
  static const String historyFileName = 'swap_history.json';

  Future<void> saveJson(Map<String, dynamic> json) async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$fileName');
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    final content = jsonEncode(json);
    await file.writeAsString(content, mode: FileMode.write);
  }

  Future<Map<String, dynamic>?> getJson() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$fileName');
    if (!await file.exists()) {
      return null;
    }
    final contents = await file.readAsString();
    final decoded = jsonDecode(contents);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return null;
  }

  /// Save a profile to storage.
  /// profileIndex: 0 for Profile 1, 1 for Profile 2
  Future<void> saveProfile(
    int profileIndex,
    Map<String, dynamic> profileData,
  ) async {
    final allProfiles = await getJson() ?? <String, dynamic>{};
    final profileKey = 'profile_$profileIndex';
    allProfiles[profileKey] = profileData;
    await saveJson(allProfiles);
  }

  /// Get a profile from storage.
  /// profileIndex: 0 for Profile 1, 1 for Profile 2
  Future<Map<String, dynamic>?> getProfile(int profileIndex) async {
    final allProfiles = await getJson();
    if (allProfiles == null) return null;
    final profileKey = 'profile_$profileIndex';
    final profile = allProfiles[profileKey];
    if (profile is Map<String, dynamic>) {
      return profile;
    }
    return null;
  }

  /// Save a swap to history.
  Future<void> saveSwapHistory(SwapHistory swap) async {
    final history = await getSwapHistory();
    history.add(swap);
    await _saveHistoryList(history);
  }

  /// Get all swap history.
  Future<List<SwapHistory>> getSwapHistory() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$historyFileName');

    if (!await file.exists()) {
      return [];
    }

    try {
      final contents = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(contents) as List<dynamic>;
      return jsonList
          .map((json) => SwapHistory.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // If file is corrupted, return empty list
      return [];
    }
  }

  /// Delete a swap from history by ID.
  Future<void> deleteSwapHistory(String swapId) async {
    final history = await getSwapHistory();
    history.removeWhere((swap) => swap.id == swapId);
    await _saveHistoryList(history);
  }

  /// Clear all swap history.
  Future<void> clearSwapHistory() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$historyFileName');
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _saveHistoryList(List<SwapHistory> history) async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$historyFileName');

    if (!await file.exists()) {
      await file.create(recursive: true);
    }

    final jsonList = history.map((swap) => swap.toJson()).toList();
    final content = jsonEncode(jsonList);
    await file.writeAsString(content, mode: FileMode.write);
  }

  Future<Profile> loadProfileToSocialRow(int profileIndex) async {
    final profileData = await getProfile(profileIndex);
    if (profileData != null) {
      final rawSocialLinks =
          profileData['socialLinks'] as Map<String, dynamic>?;
      final socialLinks = <String, String>{};

      if (rawSocialLinks != null) {
        for (final entry in rawSocialLinks.entries) {
          socialLinks[entry.key] = entry.value?.toString() ?? '';
        }
      }
      return Profile(
        name: profileData['name']?.toString() ?? '',
        id: profileIndex.toString(),
        profileName:
            profileData['profileName']?.toString() ??
            'Profile ${profileIndex + 1}',
        socialLinks: socialLinks,
      );
    } else {
      debugPrint('NO PROFILE DATA FOR INDEX $profileIndex (using defaults)');
      // Create default empty profile

      return Profile(
        id: profileIndex.toString(),
        profileName: 'Profile ${profileIndex + 1}',
        name: '',
        socialLinks: {
          'instagram': '',
          'discord': '',
          'discord_id': '',
          'twitter': '',
          'tiktok': '',
          'github': '',
          'email': '',
          'phone': '',
        },
      );
    }
  }
}
