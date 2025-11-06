import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chat_bot/chat_page.dart';

// کلاس ThemeProvider فقط در این فایل تعریف می‌شود
class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;
  
  bool get isDarkMode => _isDarkMode;
  
  ThemeProvider() {
    _loadThemePreference();
  }
  
  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('dark_mode') ?? false;
    notifyListeners();
  }
  
  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', _isDarkMode);
    notifyListeners();
  }
  
  ThemeData get themeData {
    if (_isDarkMode) {
      return ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color.fromARGB(255, 11, 114, 182),
          onPrimary: Colors.white,
          surface: Color(0xFF1E1E1E),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Color(0xFF1E1E1E),
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
      );
    } else {
      return ThemeData.light().copyWith(
        colorScheme: const ColorScheme.light(
          primary: Colors.blue,
          onPrimary: Colors.black,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.white,
          iconTheme: IconThemeData(color: Colors.black),
          titleTextStyle: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        scaffoldBackgroundColor: Colors.white,
      );
    }
  }
}

void main() async {
  // اطمینان از مقداردهی اولیه فلاتر
  WidgetsFlutterBinding.ensureInitialized();
  
  // بارگذاری متغیرهای محیطی
  await dotenv.load(fileName: "lib/assets/.env");
  
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ThemeProvider _themeProvider = ThemeProvider();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeProvider,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _themeProvider.themeData,
          home: ChatPage(themeProvider: _themeProvider),
        );
      },
    );
  }
}
