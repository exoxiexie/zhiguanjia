/// 身份证号工具（GB11643-1999）
///
/// - 18 位身份证号合法性校验（含第 18 位 MOD-11 校验码）
/// - 从身份证号解析：出生日期、性别、籍贯（省级）
/// 仅做本地格式校验，不联网核验身份真实性（后续可接公安二要素/三要素 API）。
library;

/// 校验结果
class IdCardInfo {
  /// 是否合法
  final bool valid;

  /// 不合法原因（valid=true 时为空）
  final String error;

  /// 出生日期（合法时有值，格式 yyyy-MM-dd）
  final DateTime? birthday;

  /// 性别：男 / 女（合法时有值）
  final String? gender;

  /// 籍贯省份（合法时有值，精确到省/直辖市）
  final String? province;

  const IdCardInfo({
    required this.valid,
    this.error = '',
    this.birthday,
    this.gender,
    this.province,
  });
}

class IdCardUtil {
  IdCardUtil._();

  /// 前 17 位加权因子
  static const List<int> _weights = [
    7,
    9,
    10,
    5,
    8,
    4,
    2,
    1,
    6,
    3,
    7,
    9,
    10,
    5,
    8,
    4,
    2,
  ];

  /// 加权和 mod 11 → 校验码映射
  static const List<String> _checkCodes = [
    '1',
    '0',
    'X',
    '9',
    '8',
    '7',
    '6',
    '5',
    '4',
    '3',
    '2',
  ];

  /// 省级行政区划代码（前 2 位）→ 省份名
  static const Map<String, String> _provinces = {
    '11': '北京市',
    '12': '天津市',
    '13': '河北省',
    '14': '山西省',
    '15': '内蒙古自治区',
    '21': '辽宁省',
    '22': '吉林省',
    '23': '黑龙江省',
    '31': '上海市',
    '32': '江苏省',
    '33': '浙江省',
    '34': '安徽省',
    '35': '福建省',
    '36': '江西省',
    '37': '山东省',
    '41': '河南省',
    '42': '湖北省',
    '43': '湖南省',
    '44': '广东省',
    '45': '广西壮族自治区',
    '46': '海南省',
    '50': '重庆市',
    '51': '四川省',
    '52': '贵州省',
    '53': '云南省',
    '54': '西藏自治区',
    '61': '陕西省',
    '62': '甘肃省',
    '63': '青海省',
    '64': '宁夏回族自治区',
    '65': '新疆维吾尔自治区',
    '71': '台湾省',
    '81': '香港特别行政区',
    '82': '澳门特别行政区',
  };

  /// 校验身份证号并解析信息
  static IdCardInfo validate(String id) {
    final s = id.trim().toUpperCase();
    if (s.length != 18) {
      return const IdCardInfo(valid: false, error: '身份证号须为18位');
    }
    // 前17位必须是数字
    if (!RegExp(r'^\d{17}').hasMatch(s)) {
      return const IdCardInfo(valid: false, error: '身份证号前17位须为数字');
    }
    final body = s.substring(0, 17);

    // 出生日期校验（第7-14位 yyyyMMdd）
    final year = int.tryParse(s.substring(6, 10));
    final month = int.tryParse(s.substring(10, 12));
    final day = int.tryParse(s.substring(12, 14));
    if (year == null || month == null || day == null) {
      return const IdCardInfo(valid: false, error: '出生日期格式错误');
    }
    DateTime? birthday;
    try {
      birthday = DateTime(year, month, day);
    } catch (_) {
      birthday = null;
    }
    if (birthday == null ||
        birthday.year != year ||
        birthday.month != month ||
        birthday.day != day) {
      return const IdCardInfo(valid: false, error: '出生日期不合法');
    }
    final now = DateTime.now();
    if (birthday.isAfter(now)) {
      return const IdCardInfo(valid: false, error: '出生日期不能晚于今天');
    }
    if (now.year - birthday.year > 120) {
      return const IdCardInfo(valid: false, error: '出生日期异常');
    }

    // 校验码验证
    int sum = 0;
    for (int i = 0; i < 17; i++) {
      sum += int.parse(body[i]) * _weights[i];
    }
    final expected = _checkCodes[sum % 11];
    if (s[17] != expected) {
      return const IdCardInfo(valid: false, error: '身份证号校验码错误，请核对');
    }

    // 性别：第17位奇数男、偶数女
    final genderCode = int.parse(s[16]);
    final gender = genderCode.isOdd ? '男' : '女';

    // 籍贯：前2位省份
    final province = _provinces[s.substring(0, 2)];

    return IdCardInfo(
      valid: true,
      birthday: birthday,
      gender: gender,
      province: province,
    );
  }

  /// 脱敏显示：保留前6位与后4位，中间用 * 代替
  /// 例：110101********1234
  static String mask(String id) {
    final s = id.trim();
    if (s.length != 18) return s;
    return '${s.substring(0, 6)}********${s.substring(14)}';
  }
}
