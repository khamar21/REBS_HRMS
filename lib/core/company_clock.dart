// Company time and date utilities.
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

class CompanyClock {
  final String tzName;
  final DateTime Function()? _nowUtc;
  CompanyClock(this.tzName, {this._nowUtc});

  DateTime nowUtc() => (_nowUtc?.call() ?? DateTime.now()).toUtc();

  tz.TZDateTime _local(DateTime utc) =>
      tz.TZDateTime.from(utc, tz.getLocation(tzName));

  /// Company-local date as YYYY-MM-DD
  String today() => dateOf(nowUtc());
  String dateOf(DateTime utc) => DateFormat('yyyy-MM-dd').format(_local(utc));

  /// Company-local time of a UTC timestamp, e.g. 09:41
  String timeOf(DateTime utc) => DateFormat('hh:mm a').format(_local(utc));
}
