import 'package:fatoora/data/repositories/auth_repository.dart';

class UserAuthRepository extends AuthRepository {
  UserAuthRepository({super.firebaseAuth, super.firestore, super.googleSignIn});
}
