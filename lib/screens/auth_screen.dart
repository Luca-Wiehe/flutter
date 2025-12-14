/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (C) 2020, 2021 wger Team
 *
 * wger Workout Manager is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wger/exceptions/http_exception.dart';
import 'package:wger/helpers/consts.dart';
import 'package:wger/helpers/errors.dart';
import 'package:wger/l10n/generated/app_localizations.dart';
import 'package:wger/screens/update_app_screen.dart';
import 'package:wger/theme/theme.dart';
import 'package:wger/widgets/auth/api_token_field.dart';
import 'package:wger/widgets/auth/email_field.dart';
import 'package:wger/widgets/auth/password_field.dart';
import 'package:wger/widgets/auth/server_field.dart';
import 'package:wger/widgets/auth/username_field.dart';

import '../providers/auth.dart';

enum AuthMode {
  Register,
  Login,
}

class AuthScreen extends StatelessWidget {
  const AuthScreen();

  static const routeName = '/auth';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: const SafeArea(
        child: AuthScreenContent(),
      ),
    );
  }
}

class AuthScreenContent extends StatelessWidget {
  const AuthScreenContent();

  @override
  Widget build(BuildContext context) {
    final deviceSize = MediaQuery.sizeOf(context);
    final i18n = AppLocalizations.of(context);

    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: deviceSize.height - MediaQuery.of(context).padding.top,
        ),
        child: Column(
          children: [
            // Top section: Logo and Online Mode (Login/Register)
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: wgerPrimaryColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Column(
                children: [
                  SizedBox(height: deviceSize.height * 0.04),
                  // Logo
                  const Image(
                    image: AssetImage('assets/images/logo-white.png'),
                    width: 70,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'wger',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: deviceSize.height * 0.02),
                  // Online Mode Card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.cloud_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  i18n.onlineModeTitle,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                i18n.onlineModeDescription,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.7),
                                    ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const AuthCard(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),

            // Bottom section: Offline Mode
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.smartphone_outlined,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        i18n.offlineModeTitle,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      i18n.offlineModeDescription,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      key: const Key('offlineModeButton'),
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(i18n.continueWithoutAccount),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        context.read<AuthProvider>().enterOfflineMode();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthCard extends StatefulWidget {
  const AuthCard();

  @override
  _AuthCardState createState() => _AuthCardState();
}

class _AuthCardState extends State<AuthCard> {
  bool isObscure = true;
  bool confirmIsObscure = true;
  Widget errorMessage = const SizedBox.shrink();

  final GlobalKey<FormState> _formKey = GlobalKey();
  AuthMode _authMode = AuthMode.Login;
  bool _hideCustomServer = true;
  bool _useUsernameAndPassword = true;
  final Map<String, String> _authData = {
    'username': '',
    'email': '',
    'password': '',
    'serverUrl': '',
    'apiToken': '',
  };
  var _isLoading = false;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _password2Controller = TextEditingController();
  final _emailController = TextEditingController();
  final _serverUrlController = TextEditingController(
    text: kDebugMode ? DEFAULT_SERVER_TEST : DEFAULT_SERVER_PROD,
  );
  final _apiTokenController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _password2Controller.dispose();
    _emailController.dispose();
    _serverUrlController.dispose();
    _apiTokenController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    context.read<AuthProvider>().getServerUrlFromPrefs().then((value) {
      _serverUrlController.text = value;
    });

    _preFillTextfields();
  }

  void _preFillTextfields() {
    if (kDebugMode && _authMode == AuthMode.Login) {
      setState(() {
        _usernameController.text = TESTSERVER_USER_NAME;
        _passwordController.text = TESTSERVER_PASSWORD;
      });
    }
  }

  void _resetTextfields() {
    _usernameController.clear();
    _passwordController.clear();
    _apiTokenController.clear();
  }

  void _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    _formKey.currentState!.save();
    setState(() {
      _isLoading = true;
    });

    try {
      // Login existing user
      late LoginActions res;
      if (_authMode == AuthMode.Login) {
        res = await context.read<AuthProvider>().login(
              _authData['username']!,
              _authData['password']!,
              _authData['serverUrl']!,
              _authData['apiToken'],
            );

        // Register new user
      } else {
        res = await Provider.of<AuthProvider>(context, listen: false).register(
          username: _authData['username']!,
          password: _authData['password']!,
          email: _authData['email']!,
          serverUrl: _authData['serverUrl']!,
          locale: Localizations.localeOf(context).languageCode,
        );
      }

      // Check if update is required else continue normally
      if (res == LoginActions.update && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const UpdateAppScreen()),
        );
        return;
      }
      if (context.mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } on WgerHttpException catch (error) {
      if (context.mounted) {
        setState(() {
          errorMessage = FormHttpErrorsWidget(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _switchAuthMode() {
    if (_authMode == AuthMode.Login) {
      setState(() {
        _authMode = AuthMode.Register;
        _useUsernameAndPassword = true;
      });
      _resetTextfields();
    } else {
      setState(() {
        _authMode = AuthMode.Login;
      });
      _preFillTextfields();
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            errorMessage,
            if (_useUsernameAndPassword)
              UsernameField(
                controller: _apiTokenController,
                onSaved: (value) => _authData['username'] = value!,
              ),
            if (_authMode == AuthMode.Register)
              EmailField(
                controller: _emailController,
                onSaved: (value) => _authData['email'] = value!,
              ),
            if (_useUsernameAndPassword)
              PasswordField(
                controller: _passwordController,
                onSaved: (value) => _authData['password'] = value!,
              ),

            if (_authMode == AuthMode.Register)
              StatefulBuilder(
                builder: (context, updateState) {
                  return TextFormField(
                    key: const Key('inputPassword2'),
                    decoration: InputDecoration(
                      labelText: i18n.confirmPassword,
                      prefixIcon: const Icon(Icons.password),
                      suffixIcon: IconButton(
                        icon: Icon(
                          confirmIsObscure ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () {
                          updateState(() {
                            confirmIsObscure = !confirmIsObscure;
                          });
                        },
                      ),
                    ),
                    controller: _password2Controller,
                    enabled: _authMode == AuthMode.Register,
                    obscureText: confirmIsObscure,
                    validator: _authMode == AuthMode.Register
                        ? (value) {
                            if (value != _passwordController.text) {
                              return i18n.passwordsDontMatch;
                            }
                            return null;
                          }
                        : null,
                  );
                },
              ),

            // Off-stage widgets are kept in the tree, otherwise the server URL
            // would not be saved to _authData
            if (_authMode == AuthMode.Login && !_useUsernameAndPassword)
              ApiTokenField(
                controller: _apiTokenController,
                onSaved: (value) => _authData['apiToken'] = value!,
              ),
            Offstage(
              offstage: _hideCustomServer,
              child: ServerField(
                controller: _serverUrlController,
                onSaved: (value) {
                  // Remove any trailing slash
                  if (value!.lastIndexOf('/') == (value.length - 1)) {
                    value = value.substring(0, value.lastIndexOf('/'));
                  }
                  _authData['serverUrl'] = value;
                },
              ),
            ),
            if (!_hideCustomServer)
              TextButton(
                key: const ValueKey('toggleApiTokenButton'),
                onPressed: _authMode == AuthMode.Login
                    ? () => setState(() => _useUsernameAndPassword = !_useUsernameAndPassword)
                    : null,
                child: Text(
                  _useUsernameAndPassword ? i18n.useApiToken : i18n.useUsernameAndPassword,
                ),
              ),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                key: const Key('actionButton'),
                onPressed: () {
                  if (!_isLoading) {
                    return _submit(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      )
                    : Text(
                        _authMode == AuthMode.Login ? i18n.login : i18n.register,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 12),
            Builder(
              key: const Key('toggleActionButton'),
              builder: (context) {
                final String text =
                    _authMode != AuthMode.Register ? i18n.registerInstead : i18n.loginInstead;

                return GestureDetector(
                  onTap: () => _switchAuthMode(),
                  child: Container(
                    color: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        Text(
                          text.substring(0, text.lastIndexOf('?') + 1),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          text.substring(
                            text.lastIndexOf('?') + 1,
                            text.length,
                          ),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            TextButton(
              key: const Key('toggleCustomServerButton'),
              onPressed: () {
                setState(() {
                  _hideCustomServer = !_hideCustomServer;
                  if (_hideCustomServer) {
                    _useUsernameAndPassword = true;
                  }
                });
              },
              child: Text(
                _hideCustomServer ? i18n.useCustomServer : i18n.useDefaultServer,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
