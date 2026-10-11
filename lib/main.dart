import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FloosyApp());
}

const ink = Color(0xFF152A36);
const teal = Color(0xFF087F77);
const canvas = Color(0xFFF4F7F7);

String money(num value) {
  final n = value.toStringAsFixed(0);
  return n.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',') + ' ج.م';
}

double number(String raw) => double.tryParse(raw.replaceAll(',', '').trim()) ?? 0;
String dateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
DateTime cycleStart(DateTime now) {
  if (now.day >= 27) return DateTime(now.year, now.month, 27);
  return DateTime(now.year, now.month - 1, 27);
}

class Entry {
  final String id, title, category, date, kind;
  final double amount;
  const Entry({required this.id, required this.title, required this.category, required this.date, required this.kind, required this.amount});
  factory Entry.fromMap(Map<String, dynamic> m) => Entry(
    id: m['id'] as String, title: m['title'] as String, category: m['category'] as String,
    date: m['date'] as String, kind: m['kind'] as String, amount: (m['amount'] as num).toDouble(),
  );
  Map<String, dynamic> toMap() => {'id': id, 'title': title, 'category': category, 'date': date, 'kind': kind, 'amount': amount};
}

class Goal {
  String name;
  double target, saved;
  Goal({required this.name, required this.target, this.saved = 0});
  factory Goal.fromMap(Map<String, dynamic> m) => Goal(name: m['name'], target: (m['target'] as num).toDouble(), saved: (m['saved'] as num).toDouble());
  Map<String, dynamic> toMap() => {'name': name, 'target': target, 'saved': saved};
}

class FinancialData extends ChangeNotifier {
  final SharedPreferencesAsync prefs = SharedPreferencesAsync();
  bool loading = true, configured = false;
  double salary = 0, house = 0, foodBudget = 4000, savingMonthly = 0, emergencyMonthly = 0, associations = 0;
  double openingBalance = 0, savingsBalance = 0, emergencyBalance = 0;
  String lastSalaryCycle = '';
  List<Entry> entries = [];
  List<Goal> goals = [];

  Future<void> load() async {
    try {
      final raw = await prefs.getString('floosy_data_v1');
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        configured = m['configured'] == true;
        salary = (m['salary'] as num?)?.toDouble() ?? 0;
        house = (m['house'] as num?)?.toDouble() ?? 0;
        foodBudget = (m['foodBudget'] as num?)?.toDouble() ?? 4000;
        savingMonthly = (m['savingMonthly'] as num?)?.toDouble() ?? 0;
        emergencyMonthly = (m['emergencyMonthly'] as num?)?.toDouble() ?? 0;
        associations = (m['associations'] as num?)?.toDouble() ?? 0;
        openingBalance = (m['openingBalance'] as num?)?.toDouble() ?? 0;
        savingsBalance = (m['savingsBalance'] as num?)?.toDouble() ?? 0;
        emergencyBalance = (m['emergencyBalance'] as num?)?.toDouble() ?? 0;
        lastSalaryCycle = m['lastSalaryCycle'] as String? ?? '';
        entries = ((m['entries'] as List?) ?? []).map((e) => Entry.fromMap(Map<String, dynamic>.from(e))).toList();
        goals = ((m['goals'] as List?) ?? []).map((e) => Goal.fromMap(Map<String, dynamic>.from(e))).toList();
      }
    } catch (_) {
      // A malformed local record must not crash the startup screen.
    }
    loading = false;
    notifyListeners();
  }

  Future<void> persist() async {
    notifyListeners();
    await prefs.setString('floosy_data_v1', jsonEncode({
      'configured': configured, 'salary': salary, 'house': house, 'foodBudget': foodBudget,
      'savingMonthly': savingMonthly, 'emergencyMonthly': emergencyMonthly,
      'associations': associations, 'openingBalance': openingBalance,
      'savingsBalance': savingsBalance, 'emergencyBalance': emergencyBalance,
      'lastSalaryCycle': lastSalaryCycle, 'entries': entries.map((e) => e.toMap()).toList(),
      'goals': goals.map((g) => g.toMap()).toList(),
    }));
  }

  DateTime get periodStart => cycleStart(DateTime.now());
  DateTime get periodEnd => DateTime(periodStart.year, periodStart.month + 1, 27);
  bool get salaryRecorded => lastSalaryCycle == dateKey(periodStart);
  List<Entry> get currentEntries => entries.where((e) {
    final d = DateTime.tryParse(e.date);
    return d != null && !d.isBefore(periodStart) && d.isBefore(periodEnd);
  }).toList();
  double get periodExpenses => currentEntries.where((e) => e.kind == 'expense').fold(0.0, (a, e) => a + e.amount);
  double get foodSpent => currentEntries.where((e) => e.kind == 'expense' && e.category == 'أكل').fold(0.0, (a, e) => a + e.amount);
  double get incomes => entries.where((e) => e.kind == 'income').fold(0.0, (a, e) => a + e.amount);
  double get expenses => entries.where((e) => e.kind == 'expense').fold(0.0, (a, e) => a + e.amount);
  double get totalCash => openingBalance + incomes - expenses;
  // Savings and emergency balances are earmarked amounts, not extra cash.
  double get usableCash => totalCash - savingsBalance - emergencyBalance - goals.fold(0.0, (a, g) => a + g.saved);
  double get periodAvailable {
    final scheduledHome = house - currentEntries.where((e) => e.kind == 'expense' && e.category == 'بيت').fold(0.0, (a, e) => a + e.amount);
    final scheduledAssociation = associations - currentEntries.where((e) => e.kind == 'expense' && e.category == 'جمعيات').fold(0.0, (a, e) => a + e.amount);
    final foodRemaining = foodBudget - foodSpent;
    return usableCash - [scheduledHome, scheduledAssociation, foodRemaining].fold(0.0, (a, b) => a + (b > 0 ? b : 0));
  }

  Future<void> setup({required double pay, required double homePay, required double food, required double save, required double emergency, required double gam, required double balance}) async {
    salary = pay; house = homePay; foodBudget = food; savingMonthly = save;
    emergencyMonthly = emergency; associations = gam; openingBalance = balance;
    configured = true;
    await persist();
  }

  Future<void> recordSalary() async {
    if (salaryRecorded) return;
    final start = dateKey(periodStart);
    entries.insert(0, Entry(id: DateTime.now().microsecondsSinceEpoch.toString(), title: 'المرتب', category: 'دخل', date: dateKey(DateTime.now()), kind: 'income', amount: salary));
    lastSalaryCycle = start;
    // Allocations are reservations, not extra expenses.
    savingsBalance += savingMonthly;
    emergencyBalance += emergencyMonthly;
    await persist();
  }

  Future<void> addEntry({required String title, required String category, required double amount, required String kind}) async {
    entries.insert(0, Entry(id: DateTime.now().microsecondsSinceEpoch.toString(), title: title, category: category, date: dateKey(DateTime.now()), kind: kind, amount: amount));
    await persist();
  }

  Future<void> addGoal(String name, double amount) async { goals.add(Goal(name: name, target: amount)); await persist(); }
  Future<bool> fundGoal(int i, double amount) async {
    if (i < 0 || i >= goals.length || amount <= 0 || amount > usableCash || amount > goals[i].target - goals[i].saved) return false;
    goals[i].saved += amount;
    await persist(); return true;
  }
  Future<bool> releaseSavings(double amount, bool emergency) async {
    if (amount <= 0) return false;
    if (emergency) {
      if (amount > emergencyBalance) return false;
      emergencyBalance -= amount;
    } else {
      if (amount > savingsBalance) return false;
      savingsBalance -= amount;
    }
    await persist(); return true;
  }
}

class FloosyApp extends StatefulWidget {
  const FloosyApp({super.key});
  @override State<FloosyApp> createState() => _FloosyAppState();
}
class _FloosyAppState extends State<FloosyApp> {
  final store = FinancialData();
  @override void initState() { super.initState(); store.load(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'فلوسي',
      theme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: canvas, colorScheme: ColorScheme.fromSeed(seedColor: teal), appBarTheme: const AppBarTheme(backgroundColor: canvas, foregroundColor: ink, centerTitle: true), inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)), filled: true, fillColor: Colors.white)),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: store.loading ? const Scaffold(body: Center(child: CircularProgressIndicator())) : store.configured ? HomeScreen(store: store) : SetupScreen(store: store),
    ),
  );
}

Widget surface(Widget child) => Card(elevation: 0, color: Colors.white, child: Padding(padding: const EdgeInsets.all(18), child: child));
Widget metric(String caption, String value, IconData icon, {Color color = teal}) => surface(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: color), const SizedBox(height: 12), Text(caption, style: const TextStyle(color: Colors.black54)), const SizedBox(height: 4), Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink))]));

class AmountField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  const AmountField(this.label, this.controller, {super.key});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: controller, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: label, suffixText: 'ج.م')));
}

class SetupScreen extends StatefulWidget {
  final FinancialData store;
  const SetupScreen({super.key, required this.store});
  @override State<SetupScreen> createState() => _SetupScreenState();
}
class _SetupScreenState extends State<SetupScreen> {
  final salary = TextEditingController(), home = TextEditingController(), food = TextEditingController(text: '4000'), savings = TextEditingController(), emergency = TextEditingController(), associations = TextEditingController(), balance = TextEditingController();
  @override void dispose() { for (final c in [salary, home, food, savings, emergency, associations, balance]) {c.dispose();} super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('أهلًا بيك في فلوسي')), body: ListView(padding: const EdgeInsets.all(20), children: [
    const Icon(Icons.account_balance_wallet_outlined, size: 58, color: teal), const SizedBox(height: 14), const Text('خلّينا نرتّب فلوسك', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
    const SizedBox(height: 8), const Text('دخل البيانات اللي تعرفها دلوقتي. كل المبالغ بالجنيه المصري، ويوم المرتب 27.', textAlign: TextAlign.center), const SizedBox(height: 22),
    AmountField('المرتب الشهري', salary), AmountField('مبلغ البيت الثابت', home), AmountField('حد الأكل الشهري', food), AmountField('التحويش الشهري', savings), AmountField('صندوق الطوارئ شهريًا', emergency), AmountField('أقساط الجمعيات شهريًا (إجمالي)', associations), AmountField('الرصيد الحالي المتاح بكل حساباتك', balance),
    const SizedBox(height: 8), FilledButton.icon(onPressed: () async {
      if (number(salary.text) <= 0) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب المرتب عشان نبدأ'))); return; }
      await widget.store.setup(pay: number(salary.text), homePay: number(home.text), food: number(food.text), save: number(savings.text), emergency: number(emergency.text), gam: number(associations.text), balance: number(balance.text));
    }, icon: const Icon(Icons.check), label: const Padding(padding: EdgeInsets.all(13), child: Text('ابدأ استخدام التطبيق'))),
  ]));
}

class HomeScreen extends StatefulWidget {
  final FinancialData store;
  const HomeScreen({super.key, required this.store});
  @override State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  int selected = 0;
  @override Widget build(BuildContext context) {
    final pages = [Dashboard(store: widget.store), TransactionsScreen(store: widget.store), GoalsScreen(store: widget.store), AdvisorScreen(store: widget.store), SettingsScreen(store: widget.store)];
    return Scaffold(appBar: AppBar(title: Text(['فلوسي', 'العمليات', 'أهدافي', 'مساعد الشراء', 'الإعدادات'][selected])), body: pages[selected], bottomNavigationBar: NavigationBar(selectedIndex: selected, onDestinationSelected: (i) => setState(() => selected = i), destinations: const [NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'الرئيسية'), NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'العمليات'), NavigationDestination(icon: Icon(Icons.flag_outlined), label: 'الأهداف'), NavigationDestination(icon: Icon(Icons.lightbulb_outline), label: 'المساعد'), NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'الإعدادات')]));
  }
}

class Dashboard extends StatelessWidget {
  final FinancialData store;
  const Dashboard({super.key, required this.store});
  @override Widget build(BuildContext context) {
    final period = '${store.periodStart.day}/${store.periodStart.month} - 26/${store.periodEnd.month}';
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('الدورة المالية: $period', style: const TextStyle(color: Colors.black54)), const SizedBox(height: 10),
      surface(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('المتاح الآمن بعد الالتزامات', style: TextStyle(color: Colors.black54)), const SizedBox(height: 9), Text(money(store.periodAvailable), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: store.periodAvailable < 0 ? Colors.red : teal)), const SizedBox(height: 12), Text('الرصيد الحقيقي في حساباتك: ${money(store.totalCash)}'), const SizedBox(height: 12), if (!store.salaryRecorded) FilledButton.icon(onPressed: () => _confirmSalary(context), icon: const Icon(Icons.add), label: Text('تسجيل مرتب الشهر: ${money(store.salary)}')) else const Text('✓ مرتب الدورة الحالية متسجل', style: TextStyle(color: teal))])),
      const SizedBox(height: 12), Row(children: [Expanded(child: metric('مصروفات الدورة', money(store.periodExpenses), Icons.trending_down, color: Colors.deepOrange)), Expanded(child: metric('فلوس محجوزة', money(store.savingsBalance + store.emergencyBalance), Icons.savings_outlined))]),
      const SizedBox(height: 12), surface(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('ميزانية الأكل', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)), const SizedBox(height: 8), LinearProgressIndicator(value: store.foodBudget > 0 ? (store.foodSpent / store.foodBudget).clamp(0, 1) : 0, minHeight: 10, borderRadius: BorderRadius.circular(8)), const SizedBox(height: 8), Text('${money(store.foodSpent)} من ${money(store.foodBudget)}')])),
      const SizedBox(height: 12), surface(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('حسابات مهمة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text('البيت شهريًا: ${money(store.house)}'), Text('الجمعيات شهريًا: ${money(store.associations)}'), Text('التحويش المتراكم المحجوز: ${money(store.savingsBalance)}'), Text('الطوارئ المحجوزة: ${money(store.emergencyBalance)}')])),
    ]);
  }
  Future<void> _confirmSalary(BuildContext context) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('تسجيل المرتب'), content: Text('تأكيد استلام ${money(store.salary)}؟ هيتحجز ${money(store.savingMonthly)} للتحويش و${money(store.emergencyMonthly)} للطوارئ من الرصيد المتاح.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد'))]));
    if (yes == true) await store.recordSalary();
  }
}

const expenseCategories = ['أكل', 'بيت', 'مواصلات', 'فواتير', 'جمعيات', 'ترفيه', 'اشتراكات', 'صحة', 'تسوق', 'أخرى'];
class TransactionsScreen extends StatelessWidget {
  final FinancialData store;
  const TransactionsScreen({super.key, required this.store});
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    FilledButton.icon(onPressed: () => _newExpense(context), icon: const Icon(Icons.add), label: const Padding(padding: EdgeInsets.all(12), child: Text('تسجيل مصروف'))), const SizedBox(height: 14),
    if (store.entries.isEmpty) surface(const Text('لسه مفيش عمليات. ابدأ بتسجيل مرتبك وبعدها مصاريفك.')),
    ...store.entries.map((e) => Card(elevation: 0, child: ListTile(leading: CircleAvatar(backgroundColor: e.kind == 'income' ? Colors.teal.shade50 : Colors.orange.shade50, child: Icon(e.kind == 'income' ? Icons.arrow_downward : Icons.arrow_upward, color: e.kind == 'income' ? teal : Colors.orange)), title: Text(e.title), subtitle: Text('${e.category} • ${e.date}'), trailing: Text('${e.kind == 'income' ? '+' : '-'}${money(e.amount)}', style: TextStyle(fontWeight: FontWeight.bold, color: e.kind == 'income' ? teal : ink))))),
  ]);
  Future<void> _newExpense(BuildContext context) async {
    final title = TextEditingController(), amount = TextEditingController();
    String category = expenseCategories.first;
    await showDialog<void>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(title: const Text('مصروف جديد'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: title, decoration: const InputDecoration(labelText: 'اسم المصروف')), const SizedBox(height: 12), AmountField('المبلغ', amount), DropdownButtonFormField<String>(initialValue: category, isExpanded: true, decoration: const InputDecoration(labelText: 'التصنيف'), items: expenseCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: (value) => setLocal(() => category = value ?? category))])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), FilledButton(onPressed: () async { if (number(amount.text) <= 0) return; await store.addEntry(title: title.text.trim().isEmpty ? category : title.text.trim(), category: category, amount: number(amount.text), kind: 'expense'); if (ctx.mounted) Navigator.pop(ctx); }, child: const Text('حفظ'))])));
    title.dispose(); amount.dispose();
  }
}

class GoalsScreen extends StatelessWidget {
  final FinancialData store;
  const GoalsScreen({super.key, required this.store});
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    FilledButton.icon(onPressed: () => _newGoal(context), icon: const Icon(Icons.add), label: const Padding(padding: EdgeInsets.all(12), child: Text('إضافة هدف شراء'))), const SizedBox(height: 14),
    if (store.goals.isEmpty) surface(const Text('عايز تشتري حاجة؟ اعمل هدف وحدد سعرها، وهنتابع تقدّمك.')),
    ...store.goals.asMap().entries.map((item) => surface(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.value.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 10), LinearProgressIndicator(value: item.value.target > 0 ? (item.value.saved / item.value.target).clamp(0, 1) : 0, minHeight: 9, borderRadius: BorderRadius.circular(8)), const SizedBox(height: 8), Text('${money(item.value.saved)} من ${money(item.value.target)}'), const SizedBox(height: 8), OutlinedButton(onPressed: () => _fundGoal(context, item.key), child: const Text('خصّص فلوس للهدف'))]))),
  ]);
  Future<void> _newGoal(BuildContext context) async {
    final name = TextEditingController(), price = TextEditingController();
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: const Text('هدف جديد'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الحاجة')), const SizedBox(height: 10), AmountField('سعرها', price)]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), FilledButton(onPressed: () async { if (name.text.trim().isEmpty || number(price.text) <= 0) return; await store.addGoal(name.text.trim(), number(price.text)); if (ctx.mounted) Navigator.pop(ctx); }, child: const Text('إضافة'))]));
    name.dispose(); price.dispose();
  }
  Future<void> _fundGoal(BuildContext context, int i) async {
    final amount = TextEditingController();
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: Text('الادخار لهدف ${store.goals[i].name}'), content: AmountField('مبلغ الحجز', amount), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), FilledButton(onPressed: () async { final ok = await store.fundGoal(i, number(amount.text)); if (ctx.mounted) { Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'تم حجز المبلغ للهدف' : 'المبلغ أكبر من المتاح أو المتبقي للهدف'))); } }, child: const Text('حجز'))]));
    amount.dispose();
  }
}

class AdvisorScreen extends StatefulWidget {
  final FinancialData store;
  const AdvisorScreen({super.key, required this.store});
  @override State<AdvisorScreen> createState() => _AdvisorScreenState();
}
class _AdvisorScreenState extends State<AdvisorScreen> {
  final price = TextEditingController();
  @override void dispose() {price.dispose(); super.dispose();}
  @override Widget build(BuildContext context) {
    final cost = number(price.text), available = widget.store.periodAvailable;
    final isEnough = cost > 0 && cost <= available;
    final gap = cost - available;
    return ListView(padding: const EdgeInsets.all(16), children: [
      surface(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.lightbulb_outline, color: teal, size: 40), const SizedBox(height: 10), const Text('ينفع أشتري الحاجة دي؟', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)), const SizedBox(height: 8), const Text('المساعد بيحمي مبالغ التحويش والطوارئ والالتزامات قبل أي قرار.'), const SizedBox(height: 20), TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'سعر الحاجة', suffixText: 'ج.م'), onChanged: (_) => setState(() {}))])),
      const SizedBox(height: 14), if (cost > 0) surface(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(isEnough ? Icons.check_circle_outline : Icons.warning_amber_rounded, color: isEnough ? teal : Colors.deepOrange, size: 38), const SizedBox(height: 10), Text(isEnough ? 'الشراء ممكن مبدئيًا' : 'الأفضل تأجل الشراء', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)), const SizedBox(height: 8), Text(isEnough ? 'بعد الشراء هيتبقى ${money(available - cost)} من المتاح الآمن المحسوب.' : 'ناقصك ${money(gap)} عشان تدفع من الفلوس المتاحة من غير ما تلمس التحويش أو الطوارئ أو الميزانية المحجوزة.'), const SizedBox(height: 8), const Text('القرار تقديري بناءً على الأرقام المسجلة. لازم تسجل أي التزام إضافي عشان التقدير يفضل دقيق.', style: TextStyle(color: Colors.black54))]))
      else surface(Text('الفلوس المتاحة حسب الحسابات الحالية: ${money(available)}. اكتب سعر الحاجة فوق عشان أحسبهالك.')),
    ]);
  }
}

class SettingsScreen extends StatelessWidget {
  final FinancialData store;
  const SettingsScreen({super.key, required this.store});
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    surface(const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('إعدادات فلوسي', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)), SizedBox(height: 8), Text('النسخة التجريبية تحفظ البيانات محليًا على نفس الجهاز. لا تمسح التطبيق قبل ما تنقل بياناتك، لأن النسخ الاحتياطي لم يُنفذ بعد.') ])),
    const SizedBox(height: 10), surface(Column(children: [ListTile(title: const Text('التحويش المحجوز'), subtitle: Text(money(store.savingsBalance)), trailing: const Icon(Icons.savings_outlined)), ListTile(title: const Text('صندوق الطوارئ'), subtitle: Text(money(store.emergencyBalance)), trailing: const Icon(Icons.health_and_safety_outlined)), const Divider(), TextButton(onPressed: () => _release(context, false), child: const Text('فك حجز من التحويش')), TextButton(onPressed: () => _release(context, true), child: const Text('فك حجز من الطوارئ'))])),
    const SizedBox(height: 10), surface(const Text('قفل PIN والبصمة، الحسابات المتعددة، النسخ الاحتياطي، تعديل الإعدادات، والإشعارات التلقائية: مخطط لها في الإصدارات التالية، وليست متاحة بعد.')),
  ]);
  Future<void> _release(BuildContext context, bool emergency) async {
    final amount = TextEditingController();
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: Text(emergency ? 'فك حجز الطوارئ' : 'فك حجز التحويش'), content: AmountField('المبلغ', amount), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), FilledButton(onPressed: () async { final ok = await store.releaseSavings(number(amount.text), emergency); if (ctx.mounted) { Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'تم فك الحجز' : 'المبلغ غير صالح أو أكبر من الرصيد المحجوز'))); } }, child: const Text('تأكيد'))]));
    amount.dispose();
  }
}
