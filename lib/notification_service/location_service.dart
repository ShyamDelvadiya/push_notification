import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:http/http.dart' as http;
import 'package:push_notification/notification_service/secure_storage_path.dart';

class LocationService {
  final Location _location = Location();
  StreamSubscription<LocationData>? _locationSubscription;
  final List<Map<String, dynamic>> _locationChunk =
      []; // Chunk to store location data
  final int _chunkSize = 4; // Desired chunk size
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  Future<void> initialize() async {
    try {
      await _checkLocationAccessPermissions();
      // Configure location updates
      await _location.changeSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Minimum distance to trigger updates
        interval: 10000, // Minimum interval (in ms) between updates
      );

      // // Enable persistent notification for background tracking
      // await _location.changeNotificationOptions(
      //   title: 'Location Tracking Active',
      //   subtitle: 'App is tracking your location',
      //   description: 'Your location updates are being recorded',
      //   onTapBringToFront: true,
      // );

      // Start tracking location
      startLocationTrackingAndInternetMonitering();
      debugPrint('Location tracking successfully initialized.');
    } catch (e) {
      debugPrint('Error initializing location service: $e');
    }
  }

  Future<void> _checkLocationAccessPermissions() async {
    // Step 1: Check and enable location services
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        debugPrint('Error: Location services are disabled.');
        return;
      }
    }

    // Step 2: Request foreground location permission
    PermissionStatus permissionStatus = await _location.hasPermission();
    if (permissionStatus == PermissionStatus.denied) {
      permissionStatus = await _location.requestPermission();
      if (permissionStatus != PermissionStatus.granted) {
        debugPrint('Error: Foreground location permission denied.');
        return;
      }
    }

    // Step 3: Request foreground service location permission
    /* final fgsLocationPermission = await perm.Permission.foregroundService.request();
      if (!fgsLocationPermission.isGranted) {
        debugPrint('Error: Foreground service location permission denied.');
        return;
      }*/

    // Step 4: Request background location permission (if required)
    if (permissionStatus == PermissionStatus.granted) {
      await handleBackgroundPermission();
    }
  }

  Future<void> startLocationTrackingAndInternetMonitering() async {
    print('========> location service started');
    await _checkLocationAccessPermissions();
    _monitorConnectivity();

    startLocationTracking();
  }

  Future<void> handleBackgroundPermission() async {
    // Use permission_handler to check for background location permission
    final permStatus = await perm.Permission.locationAlways.status;

    if (permStatus.isDenied || permStatus.isRestricted) {
      // Request background location permission
      final requestStatus = await perm.Permission.locationAlways.request();

      if (!requestStatus.isGranted) {
        debugPrint('Background location permission denied.');
        showPermissionExplanation(); // Explain why permission is needed
        return;
      }
    } else if (permStatus.isPermanentlyDenied) {
      debugPrint('Background location permission permanently denied.');
      showPermissionExplanation(); // Explain and guide user to settings
    }
    _location.enableBackgroundMode(enable: true);
  }

  Future<void> startLocationTracking() async {
    try {
      _locationSubscription =
          _location.onLocationChanged.listen((locationData) {
        _processLocationData(locationData);

        debugPrint(
            'New location: ${locationData.latitude}, ${locationData.longitude}');
        // Add logic to batch or send location data
      });
    } catch (e) {
      debugPrint('Error starting location tracking: $e');
    }
  }

  void _processLocationData(LocationData locationData) async {
    _locationChunk.add({
      'latitude': locationData.latitude,
      'longitude': locationData.longitude,
      'timestamp': DateTime.now().toIso8601String(),
    });
    print('location Chunk Data added --- $_locationChunk');

    if (_locationChunk.length >= _chunkSize) {
      await _sendChunkData(); // Send the chunk
    }
  }

  Future<void> _sendChunkData() async {
    final connectivityResult = await Connectivity().checkConnectivity();

    if (connectivityResult == ConnectivityResult.none) {
      debugPrint('No internet. Storing chunk locally.');
      await _storeChunkLocally();
      return;
    }

    try {
      // Combine all chunks into a single list to send as the body
      List<dynamic> allChunks = _locationChunk;
      log('========all chunks $allChunks');
      log('========all chunks ${allChunks.length}');
      final response = await http.get(
        Uri.parse(
            'https://run.mocky.io/v3/17eaffe2-5ddd-4256-9988-edc372c1d4f7'),
        // Replace with your Mocky URL
        // body: jsonEncode(allChunks),
      );

      if (response.statusCode == 200) {
        debugPrint('Chunk sent successfully.');
        await _secureStorage.delete(key: SecureStoragePath.locationChunk);
        _locationChunk.clear(); // Clear in-memory chunk
        await _sendStoredChunks(); // Attempt to send stored chunks
      } else {
        debugPrint(
            'Error: Server rejected chunk. Status code: ${response.statusCode}');
        await _storeChunkLocally();
      }
    } catch (e) {
      debugPrint('Error sending chunk: $e');
      await _storeChunkLocally();
    }
  }

  Future<void> _sendStoredChunks() async {
    List<String> storedChunks = await _getStoredChunks();

    if (storedChunks.isEmpty) {
      debugPrint('No stored chunks to send.');
      return;
    }

    try {
      // Combine all chunks into a single list to send as the body
      List<dynamic> allChunks = storedChunks
          .map((chunk) => jsonDecode(chunk)) // Decode each chunk
          .expand((chunk) => chunk) // Flatten the nested list
          .toList();
      log('============> all chunks  $allChunks');
      log('============> all chunks  ${allChunks.length}');
      /*final response = await http.post(
      Uri.parse('https://your-server.com/api/locations'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(allChunks), // Send all chunks together
    );*/
      final response = await http.get(
        Uri.parse(
            'https://run.mocky.io/v3/17eaffe2-5ddd-4256-9988-edc372c1d4f7'),
        // Replace with your Mocky URL
        // body: jsonEncode(allChunks),
      );

      if (response.statusCode == 200) {
        debugPrint('All stored chunks sent successfully.');
        _locationChunk.clear(); // Clear in-memory chunk
        await _secureStorage.delete(key: SecureStoragePath.locationChunk);
        storedChunks.clear(); // Clear the list after successful sending
      } else {
        debugPrint('Error sending stored chunks: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error sending stored chunks: $e');
    }

    // Save the remaining chunks back to storage
    await _secureStorage.write(
      key: SecureStoragePath.locationChunk,
      value: jsonEncode(storedChunks), // Save updated list
    );
  }

  Future<void> _storeChunkLocally() async {
    List<String> storedChunks = await _getStoredChunks();
    storedChunks.add(jsonEncode(_locationChunk));
    await _secureStorage.write(
      key: SecureStoragePath.locationChunk,
      value: jsonEncode(storedChunks),
    );
    _locationChunk.clear(); // Clear in-memory chunk
    debugPrint('Chunk stored locally.');
  }

  void stopLocationTracking() {
    _locationSubscription?.cancel();
    _connectivitySubscription?.cancel();
    debugPrint('Location tracking stopped.');
  }

  void showPermissionExplanation() {
    debugPrint(
        'Background location permission is required to track your location in the background. Please enable it from the app settings.');
  }

  Future<List<String>> _getStoredChunks() async {
    final storedData =
        await _secureStorage.read(key: SecureStoragePath.locationChunk);
    if (storedData != null) {
      return List<String>.from(jsonDecode(storedData));
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getReadableStoredChunks() async {
    final storedData =
        await _secureStorage.read(key: SecureStoragePath.locationChunk);

    if (storedData != null) {
      // Decode stored data and flatten the nested structure
      List<List<Map<String, dynamic>>> nestedChunks =
          List<List<Map<String, dynamic>>>.from(
        jsonDecode(storedData)
            .map((chunk) => List<Map<String, dynamic>>.from(jsonDecode(chunk))),
      );

      return nestedChunks.expand((chunk) => chunk).toList();
    }

    return [];
  }

  void _monitorConnectivity() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((connectivityResult) {
      if (connectivityResult != ConnectivityResult.none) {
        debugPrint('Internet connection restored. Sending stored chunks.');
        _sendStoredChunks();
      }
    });
  }
}
