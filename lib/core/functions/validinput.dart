import 'package:get/get.dart';

validInput(String val, int min, int max, String type) {
  if (type == "username") {
    if (!GetUtils.isUsername(val)) {
      return "not valid username".tr;
    }
  }
  // if (type == "email") {
  //   if (!GetUtils.isEmail(val)) {
  //     return "not valid email";
  //   }
  // }

  if (type == "phone") {
    if (!GetUtils.isPhoneNumber(val)) {
      return "not valid phone".tr;
    }
  }

  if (val.isEmpty) {
    return "can't be Empty".tr;
  }

  if (val.length < min) {
    return "can't be less than $min";
  }

  if (val.length > max) {
    return "can't be larger than $max";
  }
}
