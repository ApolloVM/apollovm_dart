import 'package:collection/collection.dart';

List _toListWithGenericType<T>(List list) {
  var l2 = list.map((e) => e is List ? _toListWithGenericType(e) : e).toList();

  var lString = _toListElementsOfType<String>(l2);
  if (lString != null) return lString;

  var lInt = _toListElementsOfType<int>(l2);
  if (lInt != null) return lInt;

  var lDouble = _toListElementsOfType<double>(l2);
  if (lDouble != null) return lDouble;

  var lNum = _toListElementsOfType<num>(l2);
  if (lNum != null) return lNum;

  var lBoll = _toListElementsOfType<bool>(l2);
  if (lBoll != null) return lBoll;

  // 1D

  var lListString = _toListElementsOfType<List<String>>(l2);
  if (lListString != null) return lListString;

  var lListInt = _toListElementsOfType<List<int>>(l2);
  if (lListInt != null) return lListInt;

  var lListDouble = _toListElementsOfType<List<double>>(l2);
  if (lListDouble != null) return lListDouble;

  var lListNum = _toListElementsOfType<List<num>>(l2);
  if (lListNum != null) return lListNum;

  var lListBool = _toListElementsOfType<List<bool>>(l2);
  if (lListBool != null) return lListBool;

  // 2D

  var lListString2 = _toListElementsOfType<List<List<String>>>(l2);
  if (lListString2 != null) return lListString2;

  var lListInt2 = _toListElementsOfType<List<List<int>>>(l2);
  if (lListInt2 != null) return lListInt2;

  var lListDouble2 = _toListElementsOfType<List<List<double>>>(l2);
  if (lListDouble2 != null) return lListDouble2;

  var lListNum2 = _toListElementsOfType<List<List<num>>>(l2);
  if (lListNum2 != null) return lListNum2;

  var lListBool2 = _toListElementsOfType<List<List<bool>>>(l2);
  if (lListBool2 != null) return lListBool2;

  // 3D

  var lListString3 = _toListElementsOfType<List<List<List<String>>>>(l2);
  if (lListString3 != null) return lListString3;

  var lListInt3 = _toListElementsOfType<List<List<List<int>>>>(l2);
  if (lListInt3 != null) return lListInt3;

  var lListDouble3 = _toListElementsOfType<List<List<List<double>>>>(l2);
  if (lListDouble3 != null) return lListDouble3;

  var lListNum3 = _toListElementsOfType<List<List<List<num>>>>(l2);
  if (lListNum3 != null) return lListNum3;

  var lListBool3 = _toListElementsOfType<List<List<List<bool>>>>(l2);
  if (lListBool3 != null) return lListBool3;

  //

  var lListObject3 = _toListElementsOfType<List<List<List<Object>>>>(l2);
  if (lListObject3 != null) return lListObject3;

  var lListObject2 = _toListElementsOfType<List<List<Object>>>(l2);
  if (lListObject2 != null) return lListObject2;

  var lListObject = _toListElementsOfType<List<Object>>(l2);
  if (lListObject != null) return lListObject;

  //

  var lObject = _toListElementsOfType<Object>(l2);
  if (lObject != null) return lObject;

  return l2;
}

List<T>? _toListElementsOfType<T>(List list) {
  if (_isListElementsAllOfType<T>(list)) {
    var l2 = list.cast<T>().toList();
    return l2;
  }
  return null;
}

bool _isListElementsAllOfType<T>(List list) {
  if (list is List<T>) return true;
  return list.whereType<T>().length == list.length;
}

extension CreateListTypedExtension<T> on List<T> {
  List<T> createListOfSameType() => <T>[];

  List<List<T>> createListOfSameType2D() => <List<T>>[];

  List<E> toListOfType<E>() => _toListWithGenericType<E>(this) as List<E>;
}

extension MapGetIgnoreCaseExtension<K, V> on Map<K, V> {
  V? lookupValue(Object? key, {bool ignoreCase = false}) {
    if (ignoreCase) {
      if (containsKey(key)) {
        return this[key];
      } else {
        final keyStr = key?.toString() ?? '';

        for (var e in entries) {
          if (equalsIgnoreAsciiCase(e.key?.toString() ?? '', keyStr)) {
            return e.value;
          }
        }

        return null;
      }
    } else {
      return this[key];
    }
  }
}
