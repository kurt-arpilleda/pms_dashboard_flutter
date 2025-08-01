import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../pdfViewer.dart';
import '../api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../auto_update.dart';
import 'api_serviceJP.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:mime/mime.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:unique_identifier/unique_identifier.dart';

class SoftwareWebViewScreenJP extends StatefulWidget {
  final int linkID;

  SoftwareWebViewScreenJP({required this.linkID});

  @override
  _SoftwareWebViewScreenState createState() => _SoftwareWebViewScreenState();
}

class _SoftwareWebViewScreenState extends State<SoftwareWebViewScreenJP> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ApiService apiService = ApiService();
  final ApiServiceJP apiServiceJP = ApiServiceJP();

  InAppWebViewController? webViewController;
  PullToRefreshController? pullToRefreshController;
  bool _isNavigating = false;
  Timer? _debounceTimer;
  String? _webUrl;
  String? _profilePictureUrl;
  String? _firstName;
  String? _surName;
  String? _idNumber;
  bool _isLoading = true;
  int? _currentLanguageFlag;
  double _progress = 0;
  String? _phOrJp;
  bool _isPhCountryPressed = false;
  bool _isJpCountryPressed = false;
  bool _isCountryDialogShowing = false;
  bool _isCountryLoadingPh = false;
  bool _isCountryLoadingJp = false;
  bool _isDownloadDialogShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _initializePullToRefresh();
    _fetchInitialData();
    _checkForUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    webViewController?.stopLoading();
    pullToRefreshController?.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!AutoUpdate.isUpdating) {
        _checkForUpdates();
      }
    }
  }

  void _initializePullToRefresh() {
    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
        color: Colors.blue,
      ),
      onRefresh: () async {
        if (webViewController != null) {
          _fetchAndLoadUrl();
        }
      },
    );
  }

  Future<void> _checkForUpdates() async {
    try {
      await AutoUpdate.checkForUpdate(context);
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  }

  Future<void> _fetchInitialData() async {
    await _fetchDeviceInfo();
    await _loadCurrentLanguageFlag();
    await _fetchAndLoadUrl();
    await _loadPhOrJp();
  }

  Future<void> _fetchDeviceInfo() async {
    try {
      String? deviceId = await UniqueIdentifier.serial;
      if (deviceId == null) {
        throw Exception("Unable to get device ID");
      }

      final deviceResponse = await apiServiceJP.checkDeviceId(deviceId);
      if (deviceResponse['success'] == true && deviceResponse['idNumber'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('IDNumberJP', deviceResponse['idNumber']);

        setState(() {
          _idNumber = deviceResponse['idNumber'];
        });
        await _fetchProfile(_idNumber!);
      }
    } catch (e) {
      print("Error fetching device info: $e");
    }
  }

  Future<void> _loadPhOrJp() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _phOrJp = prefs.getString('phorjp');
    });
  }

  Future<void> _fetchProfile(String idNumber) async {
    try {
      final profileData = await apiServiceJP.fetchProfile(idNumber);
      if (profileData["success"] == true) {
        String profilePictureFileName = profileData["picture"];

        String primaryUrl = "${ApiServiceJP.apiUrls[0]}V4/11-A%20Employee%20List%20V2/profilepictures/$profilePictureFileName";
        bool isPrimaryUrlValid = await _isImageAvailable(primaryUrl);

        String fallbackUrl = "${ApiServiceJP.apiUrls[1]}V4/11-A%20Employee%20List%20V2/profilepictures/$profilePictureFileName";
        bool isFallbackUrlValid = await _isImageAvailable(fallbackUrl);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('languageFlagJP', profileData["languageFlag"]);
        setState(() {
          _firstName = profileData["firstName"];
          _surName = profileData["surName"];
          _profilePictureUrl = isPrimaryUrlValid ? primaryUrl : isFallbackUrlValid ? fallbackUrl : null;
          _currentLanguageFlag = profileData["languageFlag"] ?? _currentLanguageFlag ?? 1;
        });
      }
    } catch (e) {
      print("Error fetching profile: $e");
    }
  }

  Future<bool> _isImageAvailable(String url) async {
    try {
      final response = await http.head(Uri.parse(url)).timeout(Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<void> _fetchAndLoadUrl() async {
    try {
      String url = await apiServiceJP.fetchSoftwareLink(widget.linkID);
      if (mounted) {
        setState(() {
          _webUrl = url;
          _isLoading = true;
        });
        if (webViewController != null) {
          await webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
        }
      }
    } catch (e) {
      debugPrint("Error fetching link: $e");
    }
  }

  Future<void> _loadCurrentLanguageFlag() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentLanguageFlag = prefs.getInt('languageFlagJP');
    });
  }

  Future<void> _updateLanguageFlag(int flag) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    if (_idNumber != null) {
      setState(() {
        _currentLanguageFlag = flag;
      });
      try {
        await apiServiceJP.updateLanguageFlag(_idNumber!, flag);
        await prefs.setInt('languageFlagJP', flag);

        if (webViewController != null) {
          WebUri? currentUri = await webViewController!.getUrl();
          if (currentUri != null) {
            await webViewController!.loadUrl(urlRequest: URLRequest(url: currentUri));
          } else {
            _fetchAndLoadUrl();
          }
        }
      } catch (e) {
        print("Error updating language flag: $e");
      }
    }
  }

  Future<void> _updatePhOrJp(String value) async {
    if ((value == 'ph' && _isCountryLoadingPh) || (value == 'jp' && _isCountryLoadingJp)) {
      return;
    }

    setState(() {
      if (value == 'ph') {
        _isCountryLoadingPh = true;
        _isPhCountryPressed = true;
      } else {
        _isCountryLoadingJp = true;
        _isJpCountryPressed = true;
      }
    });

    await Future.delayed(Duration(milliseconds: 100));

    try {
      String? deviceId = await UniqueIdentifier.serial;
      if (deviceId == null) {
        _showCountryLoginDialog(context, value);
        return;
      }

      dynamic service = value == "jp" ? apiServiceJP : apiService;
      final deviceResponse = await service.checkDeviceId(deviceId);

      if (deviceResponse['success'] != true || deviceResponse['idNumber'] == null) {
        _showCountryLoginDialog(context, value);
        return;
      }

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('phorjp', value);
      setState(() {
        _phOrJp = value;
      });

      if (value == "ph") {
        Navigator.pushReplacementNamed(context, '/webView');
      } else if (value == "jp") {
        Navigator.pushReplacementNamed(context, '/webViewJP');
      }
    } catch (e) {
      print("Error updating country preference: $e");
      Fluttertoast.showToast(
        msg: _currentLanguageFlag == 2
            ? "デバイス登録の確認中にエラーが発生しました: ${e.toString()}"
            : "Error checking device registration: ${e.toString()}",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
      );
    } finally {
      setState(() {
        if (value == 'ph') {
          _isCountryLoadingPh = false;
          _isPhCountryPressed = false;
        } else {
          _isCountryLoadingJp = false;
          _isJpCountryPressed = false;
        }
      });
    }
  }

  void _showCountryLoginDialog(BuildContext context, String country) {
    if (_isCountryDialogShowing) return;

    _isCountryDialogShowing = true;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Image.asset(
                country == 'ph' ?  'assets/images/philippines.png' :  'assets/images/japan.png',
                width: 26,
                height: 26,
              ),
              SizedBox(width: 8),
              Text(
                _currentLanguageFlag == 2 ? "ログインが必要です" : "Login Required",
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(fontSize: 20),
              ),
            ],
          ),
          content: Text(
            country == 'ph'
                ? (_currentLanguageFlag == 2
                ? "まずARK LOG PHアプリにログインしてください"
                : "Please login to ARK LOG PH App first")
                : (_currentLanguageFlag == 2
                ? "まずARK LOG JPアプリにログインしてください"
                : "Please login to ARK LOG JP App first"),
          ),
          actions: [
            TextButton(
              child: Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
                _isCountryDialogShowing = false;
              },
            ),
          ],
        );
      },
    ).then((_) {
      _isCountryDialogShowing = false;
    });
  }

  Future<bool> _onWillPop() async {
    if (webViewController != null && await webViewController!.canGoBack()) {
      webViewController!.goBack();
      return false;
    } else {
      return true;
    }
  }

  bool _isPdfUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    if (url.toLowerCase().endsWith('.pdf')) {
      return true;
    }

    final mimeType = lookupMimeType(url);
    if (mimeType == 'application/pdf') {
      return true;
    }

    if (uri.pathSegments.last.toLowerCase().contains('pdf')) {
      return true;
    }

    return false;
  }

  Future<void> _launchInBrowser(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } else {
      Fluttertoast.showToast(
        msg: _currentLanguageFlag == 2
            ? "ブラウザを起動できませんでした"
            : "Could not launch browser",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  Future<void> _viewPdfInternally(String url) async {
    try {
      final uri = Uri.parse(url);
      String fileName = uri.pathSegments.last;
      if (!fileName.toLowerCase().endsWith('.pdf')) {
        fileName = 'document_${DateTime.now().millisecondsSinceEpoch}.pdf';
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PDFViewerScreen(
            pdfUrl: url,
            fileName: fileName,
            languageFlag: _currentLanguageFlag ?? 1,
            shouldDeleteOnClose: true,
          ),
        ),
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: _currentLanguageFlag == 2
            ? "PDFを開く際にエラーが発生しました"
            : "Error opening PDF",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
      );
      await _launchInBrowser(url);
    }
  }

  void _showDownloadDialog(String url, bool isPdf) {
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    if (_isDownloadDialogShowing) return;

    _isDownloadDialogShowing = true;

    final uri = Uri.parse(url);
    String fileName = uri.pathSegments.last;

    if (fileName.isEmpty || fileName.length > 50) {
      fileName = isPdf
          ? 'document_${DateTime.now().millisecondsSinceEpoch}.pdf'
          : 'file_${DateTime.now().millisecondsSinceEpoch}';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: 0,
                maxHeight: constraints.maxHeight,
              ),
              child: IntrinsicHeight(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 20,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                      Text(
                        _currentLanguageFlag == 2 ? 'ダウンロード' : 'Download',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 15),
                      Text(
                        _currentLanguageFlag == 2 ? 'ファイル名:' : 'File name:',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                      SizedBox(height: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          fileName,
                          style: TextStyle(fontSize: 16),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                _currentLanguageFlag == 2 ? 'キャンセル' : 'Cancel',
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                          SizedBox(width: 15),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                Navigator.pop(context);
                                if (isPdf) {
                                  await _viewPdfInternally(url);
                                } else {
                                  await _launchInBrowser(url);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                padding: EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                isPdf
                                    ? (_currentLanguageFlag == 2 ? '表示' : 'View')
                                    : (_currentLanguageFlag == 2 ? 'ダウンロード' : 'Download'),
                                style: TextStyle(fontSize: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ).then((_) {
      _isDownloadDialogShowing = false;
    });
  }

  Future<void> _showInputMethodPicker() async {
    try {
      if (Platform.isAndroid) {
        const MethodChannel channel = MethodChannel('input_method_channel');
        await channel.invokeMethod('showInputMethodPicker');
      } else {
        Fluttertoast.showToast(
          msg: "Keyboard selection is only available on Android",
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
        );
      }
    } catch (e) {
      debugPrint("Error showing input method picker: $e");
    }
  }

  Future<void> _debounceNavigation(String url) async {
    if (_isNavigating) return;

    _debounceTimer?.cancel();

    setState(() {
      _isNavigating = true;
    });

    _debounceTimer = Timer(Duration(milliseconds: 500), () async {
      try {
        await webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      } catch (e) {
        debugPrint("Navigation error: $e");
      } finally {
        if (mounted) {
          setState(() {
            _isNavigating = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        key: _scaffoldKey,
        resizeToAvoidBottomInset: false,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(kToolbarHeight - 20),
          child: SafeArea(
            child: AppBar(
              backgroundColor: Color(0xFF3452B4),
              centerTitle: true,
              toolbarHeight: kToolbarHeight - 20,
              leading: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 30,
                icon: Icon(
                  Icons.settings,
                  color: Colors.white,
                ),
                onPressed: () {
                  _scaffoldKey.currentState?.openDrawer();
                },
              ),
              // title: _idNumber != null
              //     ? Text(
              //   "ID: $_idNumber",
              //   style: TextStyle(
              //     color: Colors.white,
              //     fontSize: 14,
              //     fontWeight: FontWeight.w500,
              //     letterSpacing: 0.5,
              //     shadows: [
              //       Shadow(
              //         color: Colors.black.withOpacity(0.2),
              //         blurRadius: 2,
              //         offset: Offset(1, 1),
              //       ),
              //     ],
              //   ),
              // )
              //     : null,
              actions: [
                IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 25,
                  icon: Container(
                    width: 25,
                    height: 25,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red,
                    ),
                    child: Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 25,
                    ),
                  ),
                  onPressed: () {
                    if (Platform.isIOS) {
                      exit(0);
                    } else {
                      SystemNavigator.pop();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        drawer: SizedBox(
          width: MediaQuery.of(context).size.width * 0.70,
          child: Drawer(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            color: Color(0xFF2053B3),
                            padding: EdgeInsets.only(top: 50, bottom: 20),
                            child: Column(
                              children: [
                                Align(
                                  alignment: Alignment.center,
                                  child: CircleAvatar(
                                    radius: 50,
                                    backgroundColor: Colors.white,
                                    backgroundImage: _profilePictureUrl != null
                                        ? NetworkImage(_profilePictureUrl!)
                                        : null,
                                    child: _profilePictureUrl == null
                                        ? FlutterLogo(size: 60)
                                        : null,
                                  ),
                                ),
                                SizedBox(height: 10),
                                Text(
                                  _firstName != null && _surName != null
                                      ? "$_firstName $_surName"
                                      : _currentLanguageFlag == 2
                                      ? "ユーザー名"
                                      : "User Name",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      overflow: TextOverflow.ellipsis,
                                      fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 5),
                                if (_idNumber != null)
                                  Text(
                                    "ID: $_idNumber",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.5,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 2,
                                          offset: Offset(1, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(height: 10),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: _currentLanguageFlag == 2 ? 35.0 : 16.0,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  _currentLanguageFlag == 2
                                      ? '言語'
                                      : 'Language',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(width: 25),
                                GestureDetector(
                                  onTap: () => _updateLanguageFlag(1),
                                  child: Column(
                                    children: [
                                      Image.asset(
                                        'assets/images/americanFlag.gif',
                                        width: 40,
                                        height: 40,
                                      ),
                                      if (_currentLanguageFlag == 1)
                                        Container(
                                          height: 2,
                                          width: 40,
                                          color: Colors.blue,
                                        ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 30),
                                GestureDetector(
                                  onTap: () => _updateLanguageFlag(2),
                                  child: Column(
                                    children: [
                                      Image.asset(
                                        'assets/images/japaneseFlag.gif',
                                        width: 40,
                                        height: 40,
                                      ),
                                      if (_currentLanguageFlag == 2)
                                        Container(
                                          height: 2,
                                          width: 40,
                                          color: Colors.blue,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.only(left: 16.0),
                            child: Row(
                              children: [
                                Text(
                                  _currentLanguageFlag == 2
                                      ? 'キーボード'
                                      : 'Keyboard',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(width: 15),
                                IconButton(
                                  icon: Icon(Icons.keyboard, size: 28),
                                  iconSize: 28,
                                  onPressed: () {
                                    _showInputMethodPicker();
                                  },
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 20),
                          Padding(
                            padding: EdgeInsets.only(
                              left: _currentLanguageFlag == 2 ? 46.0 : 30.0,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  _currentLanguageFlag == 2
                                      ? '手引き'
                                      : 'Manual',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(width: 15),
                                IconButton(
                                  icon: Icon(Icons.menu_book, size: 28),
                                  iconSize: 28,
                                  onPressed: () async {
                                    if (_idNumber == null || _currentLanguageFlag == null) return;

                                    try {
                                      final manualUrl = await apiService.fetchManualLink(widget.linkID, _currentLanguageFlag!);
                                      final fileName = 'manual_${widget.linkID}_${_currentLanguageFlag}.pdf';

                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => PDFViewerScreen(
                                            pdfUrl: manualUrl,
                                            fileName: fileName,
                                            languageFlag: _currentLanguageFlag!,
                                          ),
                                        ),
                                      );
                                    } catch (e) {
                                      Fluttertoast.showToast(
                                        msg: _currentLanguageFlag == 2
                                            ? "マニュアルの読み込み中にエラーが発生しました: ${e.toString()}"
                                            : "Error loading manual: ${e.toString()}",
                                        toastLength: Toast.LENGTH_LONG,
                                        gravity: ToastGravity.BOTTOM,
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Text(
                          _currentLanguageFlag == 2
                              ? '国'
                              : 'Country',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 25),
                        GestureDetector(
                          onTapDown: (_) => setState(() => _isPhCountryPressed = true),
                          onTapUp: (_) => setState(() => _isPhCountryPressed = false),
                          onTapCancel: () => setState(() => _isPhCountryPressed = false),
                          onTap: () => _updatePhOrJp("ph"),
                          child: AnimatedContainer(
                            duration: Duration(milliseconds: 100),
                            transform: Matrix4.identity()..scale(_isPhCountryPressed ? 0.95 : 1.0),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/philippines.png',
                                  width: 40,
                                  height: 40,
                                ),
                                if (_phOrJp == "ph" && !_isCountryLoadingPh)
                                  Opacity(
                                    opacity: 0.6,
                                    child: Icon(Icons.refresh, size: 20, color: Colors.white),
                                  ),
                                if (_isCountryLoadingPh)
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                      strokeWidth: 2,
                                    ),
                                  ),
                                if (_phOrJp == "ph")
                                  Positioned(
                                    bottom: 0,
                                    child: Container(
                                      height: 2,
                                      width: 40,
                                      color: Colors.blue,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: 30),
                        GestureDetector(
                          onTapDown: (_) => setState(() => _isJpCountryPressed = true),
                          onTapUp: (_) => setState(() => _isJpCountryPressed = false),
                          onTapCancel: () => setState(() => _isJpCountryPressed = false),
                          onTap: () => _updatePhOrJp("jp"),
                          child: AnimatedContainer(
                            duration: Duration(milliseconds: 100),
                            transform: Matrix4.identity()..scale(_isJpCountryPressed ? 0.95 : 1.0),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/japan.png',
                                  width: 40,
                                  height: 40,
                                ),
                                if (_phOrJp == "jp" && !_isCountryLoadingJp)
                                  Opacity(
                                    opacity: 0.6,
                                    child: Icon(Icons.refresh, size: 20, color: Colors.white),
                                  ),
                                if (_isCountryLoadingJp)
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                      strokeWidth: 2,
                                    ),
                                  ),
                                if (_phOrJp == "jp")
                                  Positioned(
                                    bottom: 0,
                                    child: Container(
                                      height: 2,
                                      width: 40,
                                      color: Colors.blue,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              if (_webUrl != null)
                InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(_webUrl!)),
                  initialSettings: InAppWebViewSettings(
                    mediaPlaybackRequiresUserGesture: false,
                    javaScriptEnabled: true,
                    useHybridComposition: true,
                    allowsInlineMediaPlayback: true,
                    allowContentAccess: true,
                    allowFileAccess: true,
                    cacheEnabled: true,
                    javaScriptCanOpenWindowsAutomatically: true,
                    allowUniversalAccessFromFileURLs: true,
                    allowFileAccessFromFileURLs: true,
                    useOnDownloadStart: true,
                    transparentBackground: true,
                    thirdPartyCookiesEnabled: true,
                    domStorageEnabled: true,
                    databaseEnabled: true,
                    hardwareAcceleration: true,
                    supportMultipleWindows: false,
                    useWideViewPort: true,
                    loadWithOverviewMode: true,
                    mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                    verticalScrollBarEnabled: false,
                    horizontalScrollBarEnabled: false,
                    overScrollMode: OverScrollMode.NEVER,
                    forceDark: ForceDark.OFF,
                    forceDarkStrategy: ForceDarkStrategy.WEB_THEME_DARKENING_ONLY,
                    saveFormData: true,
                    userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36",
                  ),
                  pullToRefreshController: pullToRefreshController,
                  onWebViewCreated: (controller) {
                    webViewController = controller;
                  },
                  onLoadStart: (controller, url) {
                    setState(() {
                      _isLoading = true;
                      _progress = 0;
                    });
                  },
                  onLoadStop: (controller, url) async {
                    pullToRefreshController?.endRefreshing();
                    await controller.evaluateJavascript(source: """
// First, let's be very specific about what we hide and completely exempt modals
function hideElements() {
  try {
    // Define what should NEVER be hidden (whitelist approach)
    const protectedSelectors = [
      '#modal-izi-task',
      '.modal',
      '.sweet-alert',
      '.swal',
      '[class*="swal"]',
      '[id*="modal"]',
      '.fc',
      '.fc *',
      '[class*="calendar"]'
    ];
    
    function isProtected(element) {
      // Check if element matches any protected selector
      for (let selector of protectedSelectors) {
        try {
          if (element.matches && element.matches(selector)) return true;
          if (element.closest && element.closest(selector)) return true;
        } catch (e) {
          // Ignore selector errors
        }
      }
      return false;
    }
    
    // Hide specific problematic elements only
    const specificHides = [
      'div[style*="overflow-x: hidden"]:not(#modal-izi-task):not(.modal)',
      'div[style*="overflow-x:hidden"]:not(#modal-izi-task):not(.modal)',
      'div.w3-round[style*="background: linear-gradient"]:not(#modal-izi-task):not(.modal)',
      'div.dpicture:not(#modal-izi-task):not(.modal)',
      '.dpicture:not(#modal-izi-task):not(.modal)',
      'i.fa.fa-list:not(#modal-izi-task):not(.modal)',
      'i.hamburger:not(#modal-izi-task):not(.modal)',
      '#hamburger:not(#modal-izi-task):not(.modal)',
      '.hamburger:not(#modal-izi-task):not(.modal)',
      'div[style*="#056291"]:not(#modal-izi-task):not(.modal)',
      'div[style*="background: linear-gradient(to right,white"]:not(#modal-izi-task):not(.modal)',
      'div.col-md-12.w3-padding.w3-round-large.w3-card-2:not(#modal-izi-task):not(.modal)',
      'span#taskCalendar:not(#modal-izi-task):not(.modal)',
      '#taskCalendar:not(#modal-izi-task):not(.modal)'
    ];
    
    specificHides.forEach(selector => {
      try {
        const elements = document.querySelectorAll(selector);
        elements.forEach(el => {
          if (!isProtected(el)) {
            el.style.display = 'none';
          }
        });
      } catch (e) {
        // Ignore selector errors
      }
    });
    
    // Hide navigation elements but be very careful
    const navSelectors = [
      'div.w3-bar:not(.fc):not(.fc *):not(#modal-izi-task):not(.modal)',
      'div.w3-top:not(.fc):not(.fc *):not(#modal-izi-task):not(.modal)', 
      'nav:not(.fc):not(.fc *):not(#modal-izi-task):not(.modal)',
      '.navbar:not(.fc):not(.fc *):not(#modal-izi-task):not(.modal)',
      '.nav-bar:not(.fc):not(.fc *):not(#modal-izi-task):not(.modal)',
      '.header-nav:not(.fc):not(.fc *):not(#modal-izi-task):not(.modal)',
      '.top-nav:not(.fc):not(.fc *):not(#modal-izi-task):not(.modal)'
    ];
    
    navSelectors.forEach(selector => {
      try {
        const elements = document.querySelectorAll(selector);
        elements.forEach(el => {
          if (!isProtected(el)) {
            el.style.display = 'none';
          }
        });
      } catch (e) {
        // Ignore selector errors
      }
    });
    
    // Style the time element if it exists
    const timeElement = document.querySelector('#time');
    if (timeElement && !isProtected(timeElement)) {
      timeElement.style.fontSize = '20px';
      timeElement.style.padding = '4px';
      timeElement.style.margin = '4px';
    }
    
  } catch (e) {
    console.log('Error hiding elements:', e);
  }
}

// Force show modal function
function forceShowModal() {
  const modal = document.querySelector('#modal-izi-task');
  if (modal) {
    modal.style.display = 'block !important';
    modal.style.visibility = 'visible !important';
    modal.style.opacity = '1 !important';
    modal.style.zIndex = '999999 !important';
    modal.style.position = 'fixed !important';
    
    // Also check for any parent containers that might be hidden
    let parent = modal.parentElement;
    while (parent && parent !== document.body) {
      if (parent.style.display === 'none') {
        parent.style.display = '';
      }
      if (parent.style.visibility === 'hidden') {
        parent.style.visibility = '';
      }
      parent = parent.parentElement;
    }
    
    console.log('Modal forced to show:', modal);
  } else {
    console.log('Modal #modal-izi-task not found');
  }
  
  // Also check for sweet alerts
  const sweetAlerts = document.querySelectorAll('.sweet-alert, .swal, [class*="swal"]');
  sweetAlerts.forEach(alert => {
    alert.style.display = 'block !important';
    alert.style.visibility = 'visible !important';
    alert.style.opacity = '1 !important';
    alert.style.zIndex = '999999 !important';
  });
}

// Run initial hide
hideElements();

// Create a much more conservative observer
const observer = new MutationObserver((mutations) => {
  let shouldHide = false;
  let shouldShowModal = false;
  
  mutations.forEach((mutation) => {
    if (mutation.type === 'childList') {
      mutation.addedNodes.forEach((node) => {
        if (node.nodeType === 1) {
          // If modal was added, ensure it shows
          if (node.id === 'modal-izi-task' || 
              (node.querySelector && node.querySelector('#modal-izi-task'))) {
            shouldShowModal = true;
          }
          // Only trigger hide for non-protected elements
          else if (!node.closest('#modal-izi-task') && 
                   !node.classList?.contains('modal') &&
                   !node.classList?.contains('sweet-alert') &&
                   !node.classList?.contains('swal')) {
            shouldHide = true;
          }
        }
      });
    }
  });
  
  if (shouldShowModal) {
    setTimeout(forceShowModal, 10);
  } else if (shouldHide) {
    setTimeout(hideElements, 100);
  }
});

observer.observe(document.body, {
  childList: true,
  subtree: true,
  attributes: false // Disable attribute observation to reduce interference
});

// Much less aggressive interval - only run if no modal is visible
setInterval(() => {
  const modal = document.querySelector('#modal-izi-task');
  const isModalVisible = modal && modal.offsetParent !== null;
  
  if (!isModalVisible) {
    hideElements();
  } else {
    forceShowModal(); // Ensure it stays visible
  }
}, 1000); // Reduced frequency

function injectCalendarStyles() {
  const style = document.createElement('style');
  style.innerHTML = \`
    html, body {
      margin: 0 !important;
      padding: 0 !important;
      overflow-x: hidden !important;
      width: 100% !important;
      box-sizing: border-box !important;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif !important;
      background: #f8fafc !important;
    }
    
    body {
      overflow-x: hidden !important;
    }
    
    /* CRITICAL: Ensure modals are always visible and on top */
    #modal-izi-task {
      display: block !important;
      visibility: visible !important;
      opacity: 1 !important;
      z-index: 999999 !important;
      position: fixed !important;
      pointer-events: auto !important;
    }
    
    #modal-izi-task.show,
    #modal-izi-task[style*="display: block"],
    #modal-izi-task[style*="display:block"] {
      display: block !important;
    }
    
    .modal,
    .sweet-alert,
    .swal,
    [class*="swal"],
    [id*="modal"] {
      z-index: 999999 !important;
      position: fixed !important;
      pointer-events: auto !important;
    }
    
    .modal.show,
    .modal[style*="display: block"],
    .modal[style*="display:block"] {
      display: block !important;
      visibility: visible !important;
      opacity: 1 !important;
    }
    
    /* Modern Calendar Container - Extended Width */
    .fc {
      background: #ffffff !important;
      border-radius: 16px !important; 
      box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1), 0 2px 4px -1px rgba(0,0,0,0.06) !important;
      margin: 0 -20px !important;
      overflow: hidden !important;
      border: 1px solid #e2e8f0 !important;
      width: calc(100% + 40px) !important;
      max-width: calc(100vw - 10px) !important;
      min-width: 100% !important;
      position: relative !important;
    }
    
    .fc-view-container, .fc-view, .fc-dayGridMonth-view, .fc-dayGrid-view, 
    .fc-scroller, .fc-day-grid, .fc-content-skeleton, 
    .fc-day-grid table, .fc-content-skeleton table {
      width: 100% !important;
      max-width: 100% !important;
      min-width: 100% !important;
      margin: 0 !important;
      padding: 0 !important;
      box-sizing: border-box !important;
      overflow-x: hidden !important;
      border: none !important;
    }
    
    .fc-view-container {
      width: 100% !important;
    }
    
    /* Modern Calendar Header */
    .fc-toolbar {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%) !important;
      padding: 12px 16px !important;
      margin: 0 !important;
      border-radius: 0 !important;
      display: flex !important;
      align-items: center !important;
      justify-content: space-between !important;
      flex-wrap: nowrap !important;
      width: 100% !important;
      box-sizing: border-box !important;
    }
    
    .fc-toolbar-chunk {
      display: flex !important;
      align-items: center !important;
      gap: 4px !important;
    }
    
    .fc-toolbar h2 {
      color: #ffffff !important;
      font-size: 18px !important;
      font-weight: 600 !important;
      margin: 0 !important;
      white-space: nowrap !important;
    }
    
    /* Modern Navigation Buttons */
    .fc-button {
      background: rgba(255,255,255,0.2) !important;
      border: 1px solid rgba(255,255,255,0.3) !important;
      color: #ffffff !important;
      border-radius: 6px !important;
      padding: 6px 10px !important;
      font-size: 12px !important;
      font-weight: 500 !important;
      transition: all 0.2s ease !important;
      margin: 0 2px !important;
      min-width: auto !important;
      white-space: nowrap !important;
    }
    
    .fc-button:hover {
      background: rgba(255,255,255,0.3) !important;
      border-color: rgba(255,255,255,0.4) !important;
      transform: translateY(-1px) !important;
    }
    
    .fc-button:focus {
      outline: none !important;
      box-shadow: 0 0 0 2px rgba(255,255,255,0.3) !important;
    }
    
    .fc-button-active {
      background: rgba(255,255,255,0.4) !important;
      border-color: rgba(255,255,255,0.5) !important;
    }
    
    /* Modern Day Headers */
    .fc-day-header {
      background: #f1f5f9 !important;
      color: #475569 !important;
      font-weight: 600 !important;
      font-size: 14px !important;
      padding: 12px 8px !important;
      border-bottom: 2px solid #e2e8f0 !important;
      text-transform: uppercase !important;
      letter-spacing: 0.5px !important;
      width: 14.285714% !important;
      box-sizing: border-box !important;
    }
    
    /* Modern Day Cells */
    .fc-day, .fc-day-top {
      padding: 8px !important;
      min-height: 90px !important;
      border: 1px solid #f1f5f9 !important;
      vertical-align: top !important;
      background: #ffffff !important;
      transition: background-color 0.2s ease !important;
      width: 14.285714% !important;
      box-sizing: border-box !important;
    }
    
    .fc-day:hover {
      background: #f8fafc !important;
    }
    
    .fc-day-top {
      font-size: 15px !important;
      font-weight: 600 !important;
      color: #334155 !important;
      margin-bottom: 6px !important;
    }
    
    /* Today Highlight */
    .fc-today {
      background: #eff6ff !important;
      border-color: #3b82f6 !important;
    }
    
    .fc-today .fc-day-top {
      color: #2563eb !important;
    }
    
    /* Other Month Days */
    .fc-other-month {
      background: #f8fafc !important;
      opacity: 0.6 !important;
    }
    
    .fc-other-month .fc-day-top {
      color: #94a3b8 !important;
    }
    
    /* Modern Events */
    .fc-title {
      white-space: normal !important;
      word-break: break-word !important;
      font-size: 13px !important;
      line-height: 1.3 !important;
      font-weight: 500 !important;
    }
    
    .fc-day-grid-event {
      min-height: 24px !important;
      font-size: 12px !important;
      margin: 1px 0 !important;
      padding: 3px 6px !important;
      overflow: visible !important;
      border-radius: 6px !important;
      border: none !important;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1) !important;
    }
    
    .fc-event {
      border-radius: 6px !important;
      padding: 3px 6px !important;
      font-weight: 500 !important;
      cursor: pointer !important;
      transition: all 0.2s ease !important;
    }
    
    .fc-event:hover {
      transform: translateY(-1px) !important;
      box-shadow: 0 2px 8px rgba(0,0,0,0.15) !important;
    }
    
    /* Weekend Styling */
    .fc-sun, .fc-sat {
      background: #fefefe !important;
    }
    
    /* Remove default borders */
    .fc-unthemed td, .fc-unthemed th {
      border-color: #f1f5f9 !important;
    }
    
    /* Ensure table uses full width */
    .fc table {
      width: 100% !important;
      table-layout: fixed !important;
    }
    
    /* Force full width on all calendar rows */
    .fc-row {
      width: 100% !important;
    }
    
    .fc-week {
      width: 100% !important;
    }
    
    /* Mobile Responsive */
    @media (max-width: 768px) {
      .fc {
        border-radius: 12px !important; 
        margin: 0 -15px !important;
        width: calc(100% + 30px) !important;
        max-width: calc(100vw - 5px) !important;
      }
      
      .fc-toolbar {
        padding: 10px 12px !important;
        flex-wrap: nowrap !important;
      }
      
      .fc-toolbar-chunk {
        gap: 2px !important;
      }
      
      .fc-toolbar h2 {
        font-size: 16px !important;
      }
      
      .fc-button {
        padding: 5px 8px !important;
        font-size: 11px !important;
        margin: 0 1px !important;
      }
      
      .fc-day, .fc-day-top {
        min-height: 70px !important;
        padding: 6px !important;
      }
      
      .fc-day-top {
        font-size: 14px !important;
      }
      
      .fc-event, .fc-day-grid-event {
        font-size: 11px !important;
        padding: 2px 4px !important;
      }
    }
    
    /* Smooth animations */
    * {
      transition: background-color 0.2s ease, border-color 0.2s ease !important;
    }
  \`;
  document.head.appendChild(style);
}

injectCalendarStyles();

// Enhanced click handler for ADD button
document.addEventListener('click', function(e) {
  console.log('Click detected on:', e.target);
  
  if (e.target && (
    e.target.classList.contains('fc-myCustomButton2-button') ||
    e.target.textContent?.includes('ADD') ||
    e.target.innerHTML?.includes('ADD')
  )) {
    console.log('ADD button clicked!');
    
    // Force show modal immediately
    setTimeout(forceShowModal, 10);
    setTimeout(forceShowModal, 100);
    setTimeout(forceShowModal, 500);
  }
}, true); // Use capture phase

// Also listen for any modal-related events
document.addEventListener('DOMContentLoaded', forceShowModal);
document.addEventListener('load', forceShowModal);

// Final cleanup and modal show
setTimeout(() => {
  hideElements();
  forceShowModal();
  console.log('Final setup complete');
}, 2000);

// Debug: Log when modal appears in DOM
const modalObserver = new MutationObserver((mutations) => {
  mutations.forEach((mutation) => {
    mutation.addedNodes.forEach((node) => {
      if (node.nodeType === 1 && (node.id === 'modal-izi-task' || node.querySelector('#modal-izi-task'))) {
        console.log('Modal detected in DOM!');
        setTimeout(forceShowModal, 0);
      }
    });
  });
});

modalObserver.observe(document.body, { childList: true, subtree: true });
""");
                    setState(() {
                      _isLoading = false;
                      _progress = 1;
                    });
                  },
                  onProgressChanged: (controller, progress) {
                    setState(() {
                      _progress = progress / 100;
                    });
                  },
                  onReceivedServerTrustAuthRequest: (controller, challenge) async {
                    return ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.PROCEED);
                  },
                  onPermissionRequest: (controller, request) async {
                    List<Permission> permissionsToRequest = [];

                    if (request.resources.contains(PermissionResourceType.CAMERA)) {
                      permissionsToRequest.add(Permission.camera);
                    }
                    if (request.resources.contains(PermissionResourceType.MICROPHONE)) {
                      permissionsToRequest.add(Permission.microphone);
                    }

                    Map<Permission, PermissionStatus> statuses = await permissionsToRequest.request();
                    bool allGranted = statuses.values.every((status) => status.isGranted);

                    return PermissionResponse(
                      resources: request.resources,
                      action: allGranted ? PermissionResponseAction.GRANT : PermissionResponseAction.DENY,
                    );
                  },
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    final url = navigationAction.request.url?.toString() ?? '';

                    // Convert specific HTTP URLs to HTTPS
                    if (url.startsWith('http://192.168.1.213/V4/Common%20Software/Item%20Location%20Input%20Software%20v3.0/raymond_itemLocationInputFormv3.0.php') ||
                        url.startsWith('http://220.157.175.232/V4/Common%20Software/Item%20Location%20Input%20Software%20v3.0/raymond_itemLocationInputFormv3.0.php')) {
                      final httpsUrl = url.replaceFirst('http://', 'https://');
                      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(httpsUrl)));
                      return NavigationActionPolicy.CANCEL;
                    }

                    final isPdf = _isPdfUrl(url);
                    if (isPdf || lookupMimeType(url) != null) {
                      _showDownloadDialog(url, isPdf);
                      return NavigationActionPolicy.CANCEL;
                    }

                    _debounceNavigation(url);
                    return NavigationActionPolicy.CANCEL;
                  },
                  onDownloadStartRequest: (controller, downloadStartRequest) async {
                    final url = downloadStartRequest.url.toString();
                    final isPdf = _isPdfUrl(url);
                    _showDownloadDialog(url, isPdf);
                  },
                ),
              if (_isLoading)
                LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
            ],
          ),
        ),
      ),
    );
  }
}