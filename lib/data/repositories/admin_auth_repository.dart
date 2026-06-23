import 'package:fatoora/data/repositories/auth_repository.dart';

class AdminAuthRepository extends AuthRepository {
  AdminAuthRepository({
    super.firebaseAuth,
    super.firestore,
    super.googleSignIn,
  });
}
