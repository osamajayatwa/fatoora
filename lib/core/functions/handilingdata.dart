import 'package:fatoora/core/class/statusrequest.dart';


handilingData(response) {
  if (response is StatusRequest) {
    return response;
  } else {
    return StatusRequest.success;
  }
}
